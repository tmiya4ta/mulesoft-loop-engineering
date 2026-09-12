#!/usr/bin/env python3
# client-id-enforcement を「付いている」から「守れている」にするための、消費側の作業。
# 消費アプリを作り、API インスタンスと契約を結び、**秘密の値を一度も出さずに**疎通を確かめる。
#
# なぜ要るか。client-id-enforcement は**契約が無いと必ず 401** を返す。付けただけでは
# 「守れている」のか「経路が壊れている」のか区別できない (401 は経路が正しい証拠にならない —
# knowledge/gotchas/api-manager.md)。区別するには、契約を持つ資格情報で 200 を見るしかない。
#
# 使い方:
#   python3 scripts/contract.py app-list                          消費アプリの一覧 (id と名前だけ)
#   python3 scripts/contract.py app-create <名前> [--api <インスタンス>]   消費アプリを作る
#   python3 scripts/contract.py create <applicationId> <インスタンス>      契約を結ぶ
#   python3 scripts/contract.py list <applicationId>              そのアプリの契約
#   python3 scripts/contract.py check <applicationId> <base-url> [<path>]  ヘッダ有無で 200/401 を実測
# <インスタンス> は API インスタンス ID / instanceLabel / assetId (policy.py と同じ解決)。
# どの verb にも `--dry-run` を付けられる。**送る本文を見せるだけで、何も作らない。**
#
# **秘密の値を出力しません。** app-create が返す clientId / clientSecret も表示しません。
# 疎通は `check` が内部で取り、**環境変数として policy-check.sh に渡して**判定します
# (コマンド行にも ps にも残らない)。値が要るときは人が Anypoint の画面で見てください。
#
# **app-create と create は `context/deployment/authorizations.yaml` の `contract.sandbox: allowed`
# が要る** (無ければ `policy.sandbox` を見る — 契約はポリシーを効かせるための付帯作業なので、
# 古い authorizations.yaml でも止まらないようにしてある)。書き換えるのは人。
# 環境名が Production 系なら、許可があっても止まる。
#
# 本文の項目は**推測していません**。公式ポータルの OAS から取った必須項目です:
#   POST /exchange/api/v2/organizations/{masterOrg}/applications        (createClientApplication)
#     name / description / grantTypes / redirectUri / url
#   POST .../applications/{applicationId}/contracts                     (createApplicationContract)
#     必須: acceptedTerms, instanceType(api), organizationId, groupId, assetId, version,
#           versionGroup, apiId   (任意: environmentId, requestedTierId)
#   出典: dev-portal.mulesoft.com/apis/exchange-experience/schemas/client-applications.yaml
#         (#/BaseCreateContractV2 と #/CreateContractForAPIV2)
#
# exit 0 = できた / 1 = API が失敗した、見つからない / 2 = 前提が無い (許可、資格情報、引数)
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from policy import (api, ascii_downcase, err, errb, fail, http, jq_get,  # noqa: E402
                    jq_tostring, loads, out, read_lines, _resolve, subshell)

HOST = os.environ.get("ANYPOINT_HOST") or "https://anypoint.mulesoft.com"
EX = HOST + "/exchange/api/v2/organizations"


def usage():
    for ln in read_lines(os.path.abspath(__file__)):
        if ln.startswith("#!"):
            continue
        if not ln.startswith("#"):
            break
        err(ln[2:] if ln.startswith("# ") else ln[1:])
    sys.exit(2)


def project_root():
    """authorizations.yaml を持つ上位ディレクトリ (無ければ "")。deploy-guard と同じ形。"""
    d = os.getcwd()
    while d:
        if os.path.isfile(os.path.join(d, "context/deployment/authorizations.yaml")):
            return d
        if os.path.exists(os.path.join(d, ".git")):
            return ""
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent
    return ""


def allowed_value(auth, block):
    """authorizations.yaml の <block>: の下の sandbox: の値。無ければ ""。"""
    ok, inside = "", False
    for ln in (read_lines(auth) if auth else []):
        if not inside:
            if re.search(r"^%s:" % block, ln):
                inside = True
            continue
        if re.search(r"^[^ ]", ln):
            inside = False
            continue
        m = re.match(r"^[ \t]*sandbox:[ \t]*([a-z-]*)", ln)
        if m:
            return m.group(1)
    return ok


def need_allowed(verb):
    """書き込みの許可を確かめる。**contract が無ければ policy を見る** (古い許可ファイルで止めない)。"""
    root = project_root()
    auth = os.path.join(root, "context/deployment/authorizations.yaml") if root else ""
    ok = allowed_value(auth, "contract")
    which = "contract.sandbox"
    if not ok:
        ok = allowed_value(auth, "policy")
        which = "policy.sandbox (contract: が無いので代わりに見た)"
    if ok != "allowed":
        err("contract: authorizations.yaml の %s が '%s' なので %s はしない。" % (which, ok or "無し", verb))
        err("  許可を書くのは人 (%s)。**自分で書き換えない。**"
            % (auth or "context/deployment/authorizations.yaml"))
        err("  理由をそのまま人に伝えて止まる。")
        sys.exit(2)
    envname = os.environ.get("ANYPOINT_ENV") or ""
    if not envname:
        for ln in read_lines(os.path.join(root or ".", "context/deployment/sandbox.yaml")):
            m = re.match(r"^environment:[ \t]*([^#]*)", ln)
            if m:
                envname = m.group(1).strip().strip('"')
                break
    low = ascii_downcase(envname)
    if "prod" in low or "本番" in low:
        err("contract: 環境 '%s' は本番系。許可があっても止まる (本番は人が手で行う)" % envname)
        sys.exit(2)
    return root


def token():
    """access_token。**Secret は POST の本文なので argv にもプロセス一覧にも残らない。**"""
    body = subshell(lambda: json.dumps({
        "grant_type": "client_credentials",
        "client_id": _need_env("ANYPOINT_CLIENT_ID"),
        "client_secret": _need_env("ANYPOINT_CLIENT_SECRET"),
    }))
    _, tb = http(HOST + "/accounts/api/v2/oauth2/token",
                 headers={"content-type": "application/json"},
                 data=body.encode("utf-8"), method="POST", timeout=30)
    tok = jq_tostring(jq_get(loads(tb), "access_token"))
    if not tok or tok == "null":
        err("contract: トークンが取れない (ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET を確かめる)")
        sys.exit(2)
    return tok


def _need_env(name):
    v = os.environ.get(name)
    if not v:
        err("contract: 環境変数 %s が要る。**値を会話にもコマンド行にも書かない。**" % name)
        err("  人に頼む: export %s=... してから claude を起動し直す" % name)
        sys.exit(2)
    return v


def master_org(tok):
    """ルート組織 ID。business group を使っていると API インスタンスの organizationId と違う。"""
    v = os.environ.get("ANYPOINT_MASTER_ORG")
    if v:
        return v
    code, b = http(HOST + "/accounts/api/me", headers={"Authorization": "Bearer " + tok}, timeout=30)
    if code != "200":
        err("contract: /accounts/api/me が HTTP %s。ANYPOINT_MASTER_ORG で渡してください" % code)
        sys.exit(1)
    me = loads(b)
    mid = jq_get(me, "user", "organization", "id")
    if not mid:
        mid = jq_get(me, "user", "organizationId")
    if not mid:
        err("contract: ルート組織 ID が /accounts/api/me から読めない。ANYPOINT_MASTER_ORG で渡してください")
        sys.exit(1)
    return jq_tostring(mid)


def instance(api_id):
    """API Manager のインスタンス。契約の必須項目はここから取る (推測しない)。"""
    rc, b = api("/apimanager/api/v1/organizations/{org}/environments/{env}/apis/" + api_id)
    if rc != 0:
        fail(rc)
    return loads(b)


def send(tok, url, obj, dry, what):
    """POST。--dry-run なら送らずに本文を見せる (秘密は本文に入らない)。"""
    body = json.dumps(obj, ensure_ascii=False, indent=2)
    if dry:
        out("contract: --dry-run なので送りません。%s に送る本文:" % what)
        out("  POST " + url)
        for ln in body.splitlines():
            out("  " + ln)
        return None, "200"
    code, b = http(url, headers={"Authorization": "Bearer " + tok, "content-type": "application/json"},
                   data=body.encode("utf-8"), method="POST", timeout=60)
    if code not in ("200", "201"):
        err("contract: %s が HTTP %s" % (what, code))
        errb(b[:1200])
        err()
        err("  **本文の項目は推測で足さないこと。** エラー本文が挙げた項目だけを埋め、")
        err("  それでも通らなければ K ファイルに残して人に聞く。")
        sys.exit(1)
    return loads(b), code


def cmd_app_list(argv, dry):
    tok = token()
    m = master_org(tok)
    code, b = http("%s/%s/applications" % (EX, m), headers={"Authorization": "Bearer " + tok}, timeout=60)
    if code != "200":
        err("contract: 一覧が HTTP %s" % code)
        errb(b[:800])
        sys.exit(1)
    data = loads(b)
    rows = data if isinstance(data, list) else (jq_get(data, "data") or [])
    if not rows:
        out("contract: 消費アプリはまだありません (app-create で作る)")
        return
    out("%-38s %s" % ("applicationId", "name"))
    for r in rows:
        out("%-38s %s" % (jq_tostring(jq_get(r, "id")), jq_tostring(jq_get(r, "name"))))


def maybe_token(dry):
    """--dry-run で資格情報がまだ無いときは (None, "{masterOrg}")。本文の形だけは見せられる。"""
    if dry and not (os.environ.get("ANYPOINT_CLIENT_ID") and os.environ.get("ANYPOINT_CLIENT_SECRET")):
        out("contract: (--dry-run、資格情報なし) 組織 ID は {masterOrg} のまま見せます。")
        return None, "{masterOrg}"
    tok = token()
    return tok, master_org(tok)


def cmd_app_create(argv, dry):
    if not argv:
        err("使い方: contract.py app-create <名前> [--api <インスタンス>]")
        sys.exit(2)
    name = argv[0]
    api_ref = ""
    if "--api" in argv:
        i = argv.index("--api")
        if i + 1 >= len(argv):
            err("--api にはインスタンス (ID / instanceLabel / assetId) が要る")
            sys.exit(2)
        api_ref = argv[i + 1]
    if not dry:
        need_allowed("app-create")
    tok, m = maybe_token(dry)
    url = "%s/%s/applications" % (EX, m)
    if api_ref:
        api_id = "{apiInstanceId}" if tok is None else subshell(lambda: _resolve(api_ref))
        url += "?apiInstanceId=" + api_id
    # grantTypes は client_credentials だけにする。client-id-enforcement が使うのはこれだけで、
    # 余計な grant を足すと使わない経路が開く。redirectUri / url は client_credentials には不要。
    obj = {"name": name, "description": name, "grantTypes": ["client_credentials"],
           "redirectUri": [], "url": ""}
    got, _ = send(tok, url, obj, dry, "消費アプリの作成")
    if dry:
        return
    out("contract: 消費アプリを作りました。applicationId = %s" % jq_tostring(jq_get(got, "id")))
    out("  **clientId / clientSecret は表示しません。** 契約のあとは `check` が内部で使います。")
    out("  次: python3 scripts/contract.py create %s <インスタンス>" % jq_tostring(jq_get(got, "id")))


def _contract_body(inst, api_id):
    """契約の必須項目をインスタンスから埋める。**足りないものは名前を挙げて止まる** (推測しない)。"""
    fields = {
        "organizationId": jq_get(inst, "organizationId"),
        "groupId": jq_get(inst, "groupId"),
        "assetId": jq_get(inst, "assetId"),
        "version": jq_get(inst, "assetVersion"),
        "versionGroup": jq_get(inst, "productVersion"),
        "environmentId": jq_get(inst, "environmentId"),
    }
    missing = [k for k, v in fields.items()
               if k != "environmentId" and (v is None or jq_tostring(v) in ("", "null"))]
    if missing:
        err("contract: API インスタンスの応答に %s がありません。" % " / ".join(missing))
        err("  推測で埋めません。応答を見て、どの項目が対応するかを確かめてください:")
        err("    python3 scripts/anypoint-api.py "
            "'/apimanager/api/v1/organizations/{org}/environments/{env}/apis/%s'" % api_id)
        err("  分かったら K ファイルに書いて、/mule-learn でプラグインに返してください。")
        sys.exit(1)
    body = {"acceptedTerms": True, "instanceType": "api", "apiId": str(api_id)}
    for k, v in fields.items():
        if v is not None and jq_tostring(v) not in ("", "null"):
            body[k] = jq_tostring(v)
    return body


def cmd_create(argv, dry):
    if len(argv) < 2:
        err("使い方: contract.py create <applicationId> <インスタンス>")
        sys.exit(2)
    app_id, api_ref = argv[0], argv[1]
    if not dry:
        need_allowed("create")
    if dry and not os.environ.get("ANYPOINT_CLIENT_ID"):
        err("contract: create の --dry-run は資格情報が要ります。")
        err("  契約の本文はインスタンスの応答 (groupId / assetId / version / versionGroup) から")
        err("  埋めるので、**推測では見せられません**。")
        sys.exit(2)
    tok = token()
    m = master_org(tok)
    api_id = subshell(lambda: _resolve(api_ref))
    body = _contract_body(instance(api_id), api_id)
    url = "%s/%s/applications/%s/contracts" % (EX, m, app_id)
    got, _ = send(tok, url, body, dry, "契約の作成")
    if dry:
        return
    out("contract: 契約を結びました (id = %s, status = %s)"
        % (jq_tostring(jq_get(got, "id")), jq_tostring(jq_get(got, "status"))))
    out("  **付けただけでは守れているか分かりません。** 次に実測してください:")
    out("  python3 scripts/contract.py check %s <base-url> [<path>]" % app_id)


def cmd_list(argv, dry):
    if not argv:
        err("使い方: contract.py list <applicationId>")
        sys.exit(2)
    tok = token()
    m = master_org(tok)
    code, b = http("%s/%s/applications/%s/contracts" % (EX, m, argv[0]),
                   headers={"Authorization": "Bearer " + tok}, timeout=60)
    if code != "200":
        err("contract: 一覧が HTTP %s" % code)
        errb(b[:800])
        sys.exit(1)
    rows = loads(b)
    rows = rows if isinstance(rows, list) else (jq_get(rows, "contracts") or [])
    if not rows:
        out("contract: このアプリに契約はありません")
        return
    out("%-38s %-10s %s" % ("contractId", "status", "apiId"))
    for r in rows:
        out("%-38s %-10s %s" % (jq_tostring(jq_get(r, "id")), jq_tostring(jq_get(r, "status")),
                                jq_tostring(jq_get(r, "apiId"))))


def _credentials(tok, m, app_id):
    """clientId / clientSecret を取る。**返すだけで、決して出力しない。**"""
    code, b = http("%s/%s/applications/%s" % (EX, m, app_id),
                   headers={"Authorization": "Bearer " + tok}, timeout=60)
    if code != "200":
        err("contract: アプリの取得が HTTP %s" % code)
        errb(b[:800])
        sys.exit(1)
    a = loads(b)
    cid = jq_tostring(jq_get(a, "clientId"))
    sec = jq_tostring(jq_get(a, "clientSecret"))
    if not cid or cid == "null" or not sec or sec == "null":
        err("contract: 応答に clientId / clientSecret がありません (権限か、アプリの種類を確かめる)")
        sys.exit(1)
    return cid, sec


def cmd_check(argv, dry):
    if len(argv) < 2:
        err("使い方: contract.py check <applicationId> <base-url> [<path>]")
        sys.exit(2)
    app_id, base = argv[0], argv[1]
    path = argv[2] if len(argv) > 2 else ""
    if dry:
        out("contract: --dry-run なので叩きません。実測するときは --dry-run を外してください。")
        return
    tok = token()
    m = master_org(tok)
    cid, sec = _credentials(tok, m, app_id)
    check = os.path.join(HERE, "policy-check.sh")
    if not os.path.isfile(check):
        err("contract: %s がありません (プラグインの同期を確かめる)" % check)
        sys.exit(2)
    # **値は環境変数で渡す。** コマンド行に置くと ps に出る。policy-check.sh は CLIENT_ID /
    # CLIENT_SECRET から読む作りなので、そのまま渡せる。
    env = dict(os.environ, CLIENT_ID=cid, CLIENT_SECRET=sec)
    cmd = ["bash", check, base, "client-id"] + ([path] if path else [])
    r = subprocess.run(cmd, env=env)
    sys.exit(r.returncode)


VERBS = {"app-list": cmd_app_list, "app-create": cmd_app_create,
         "create": cmd_create, "list": cmd_list, "check": cmd_check}


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    argv = [a for a in argv if a != "--dry-run"]
    if not argv or argv[0] in ("-h", "--help", "help"):
        usage()
    f = VERBS.get(argv[0])
    if not f:
        err("contract: 知らない verb '%s'" % argv[0])
        usage()
    f(argv[1:], dry)


if __name__ == "__main__":
    main()
