#!/usr/bin/env python3
# API Manager のポリシーを、探す / 設定項目を見る / 一覧する / 付ける / 外す。
#
# なぜ必要か。ポリシーは「どの資産を、どの設定で付けるか」が分からないと 1 行も書けないのに、
# 資産の座標 (groupId / assetId / version) も設定キーも画面にしか無いと思われていた。実際は
# Exchange とポリシーのスキーマから取れる。**しかも設定は検証されない** — 存在しないキーを渡しても
# 201 が返り、「適用済み」として一覧に並ぶ (実測)。推測すると、間違いに気付けないまま進む。
# 設定キーは `config` で取ってから書き、効いたかは `policy-check.sh` で実測する。
#
# 使い方:
#   python3 scripts/policy.py find <語>                     付けられるポリシーを探す (assetId と version)
#   python3 scripts/policy.py config <assetId> [<version>]  そのポリシーの設定キー (推測しないために必ず見る)
#   python3 scripts/policy.py list <インスタンス>            そのインスタンスに今付いているもの (policyId と順)
#   python3 scripts/policy.py apply <インスタンス> <assetId> [<version>] [--config '<JSON>'|@<file>]
#   python3 scripts/policy.py remove <インスタンス> <policyId>
# <インスタンス> は API インスタンス ID / instanceLabel / assetId (gateway-public-url.py と同じ)。
#
# **apply と remove は `context/deployment/authorizations.yaml` の `policy.sandbox: allowed` が要る。**
# 書き換えるのは人。エージェントは読むだけ。環境名が Production 系なら、許可があっても止まる。
# 資格情報は anypoint-api.py と同じ環境変数 (ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)。
#
# 実測 (2026-09-12、flexGateway のインスタンス):
#   apply  → 201。作られたポリシーの JSON が返る (`id` が policyId)。**実装資産は自動で選ばれる**
#            (client-id-enforcement 1.3.3 を付けると implementationAsset は client-id-enforcement-flex 1.2.0)
#   remove → 204 (本文なし)。一覧から消える
#   付けただけでは守れない。**必ず `policy-check.sh` で実測する** (認証なし 401 / あり 2xx)。
#
# exit 0 = できた / 1 = API が失敗した、見つからない / 2 = 前提が無い (許可、資格情報、引数)
#
# --- bash 版 (policy.py) からの移植メモ ---------------------------------------------------
# jq と curl への依存を外すのが目的なので、JSON は標準ライブラリの json、HTTP は urllib.request で行う。
# 元の api() (python3 scripts/anypoint-api.py を呼ぶ) は、同じディレクトリの anypoint-api.py を
# sys.executable で呼ぶ形にしてある (呼ばれる側は単体でも CLI として動く)。
# usage() が「上のコメントを sed で切り出して出す」形なのもそのまま (上のコメントが出力そのもの)。
# resolve() を `id=$(resolve ...)` で呼ぶと、resolve の中の exit は**コマンド置換の部分シェルだけ**を
# 終わらせて本体は続く、という元の bash の挙動も写してある (subshell() を参照)。
# 表の桁揃えは mawk の printf と同じで**バイト**で詰める (日本語が入る列で見え方が変わるため)。
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))     # here=$(cd "$(dirname "$0")" && pwd)
ERRBUF = bytearray()                                  # err=$(mktemp)
EXCHANGE_POLICY_GROUP = "68ef9520-24e9-4cf2-b2f5-620025690913"   # MuleSoft の公式ポリシー資産の groupId
AM = "/apimanager/api/v1/organizations/{org}/environments/{env}/apis"


# --- bash の細かい意味を写す道具 --------------------------------------------------------
def out(s=""):
    sys.stdout.buffer.write(s.encode("utf-8") + b"\n")
    sys.stdout.flush()


def outb(b):
    sys.stdout.buffer.write(b)
    sys.stdout.flush()


def err(s=""):
    sys.stdout.flush()
    sys.stderr.buffer.write(s.encode("utf-8") + b"\n")
    sys.stderr.flush()


def errb(b):
    sys.stdout.flush()
    sys.stderr.buffer.write(b)
    sys.stderr.flush()


def param_required(value, param, msg):
    """bash の ${N:?msg}。未設定か空なら診断を出して exit 1 (bash と同じ形・同じ終了コード)。"""
    if value is None or value == "":
        err("%s: line %d: %s: %s" % (sys.argv[0], sys._getframe(1).f_lineno, param, msg))
        sys.exit(1)
    return value


def subshell(f):
    """bash の $( ... )。中で exit しても部分シェルが終わるだけで、本体は続く (取れる値は空)。"""
    try:
        return f()
    except SystemExit:
        return ""


def bpad(s, n):
    """mawk の printf "%-Ns"。mawk はバイトで詰めるので、日本語の列は見た目より短く詰まる。"""
    b = s.encode("utf-8") if isinstance(s, str) else s
    return b + b" " * max(0, n - len(b))


class JNum:
    """JSON の数を**元の字面のまま**持つ (jq 1.7 以降と同じ見え方にするため)。"""

    __slots__ = ("text",)

    def __init__(self, text):
        self.text = text

    def __str__(self):
        return self.text

    def __eq__(self, o):
        return isinstance(o, JNum) and self.text == o.text

    def __hash__(self):
        return hash(self.text)


class JqError(Exception):
    """jq がエラーで止まるところ (オブジェクト以外を .key で辿った、など)。"""


def loads(b):
    """json.loads。数は JNum にして字面を保つ。失敗したら None (jq がパースエラーで止まるのと同じ)。"""
    try:
        if isinstance(b, (bytes, bytearray)):
            b = b.decode("utf-8")
        return json.loads(b, parse_int=JNum, parse_float=JNum)
    except Exception:
        return None


def jq_tostring(v):
    """jq の文字列補間 \\(...) / tostring と同じ形。"""
    if isinstance(v, str):
        return v
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, JNum):
        return v.text
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"), default=str)


def jq_get(o, *keys):
    """jq の .a.b.c。null を辿ると null。オブジェクト以外を辿ったら jq はエラーだが、ここは None。"""
    for k in keys:
        if o is None or not isinstance(o, dict):
            return None
        o = o.get(k)
    return o


def jq_index(o, k):
    """jq の .key。オブジェクト以外 (null を除く) を辿ったら jq と同じくエラーにする。"""
    if o is None:
        return None
    if isinstance(o, dict):
        return o.get(k)
    raise JqError


def jq_iter(v):
    """jq の .[]? 。配列はそのまま、オブジェクトは値、それ以外は何も出さない。"""
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return list(v.values())
    return []


def jq_alt(v, other):
    """jq の `v // other`。null と false だけが偽。"""
    return other if (v is None or v is False) else v


def jq_empty(v):
    """jq -r '... // empty' の結果 (null / false なら空文字)。"""
    return "" if (v is None or v is False) else jq_tostring(v)


def jq_recurse(v):
    """jq の `..`。自分を出してから子へ (深さ優先・先行順)。"""
    yield v
    if isinstance(v, dict):
        for x in v.values():
            yield from jq_recurse(x)
    elif isinstance(v, list):
        for x in v:
            yield from jq_recurse(x)


def jq_sort_key(v):
    """jq の並び: null < false < true < 数 < 文字列 < 配列 < オブジェクト。"""
    if v is None:
        return (0,)
    if v is False:
        return (1,)
    if v is True:
        return (2,)
    if isinstance(v, JNum):
        return (3, float(v.text))
    if isinstance(v, str):
        return (4, v)
    if isinstance(v, list):
        return (5, [jq_sort_key(x) for x in v])
    return (6, sorted(v.keys()))


def ascii_downcase(s):
    """tr '[:upper:]' '[:lower:]' と同じ (GNU tr はバイト単位なので A-Z だけ)。"""
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)


def read_lines(path):
    """sed と同じく 1 行ずつ。無いファイルは空 (元も 2>/dev/null で握りつぶしている)。"""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except Exception:
        return []


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """curl は -L 無しではリダイレクトを追わないので、urllib も追わない。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(NoRedirect)


def http(url, headers=None, data=None, method=None, timeout=60):
    """(HTTP の状態コードの文字列, 本文のバイト列)。届かなければ ("000", b"")。
    curl -sS -o <file> -w '%{http_code}' と同じ。curl と違い、届かない理由は標準エラーに出ない。"""
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "*/*")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with _opener.open(req, timeout=timeout) as r:
            return str(r.status), r.read()
    except urllib.error.HTTPError as e:
        try:
            body = e.read()
        except Exception:
            body = b""
        return str(e.code), body
    except Exception:
        return "000", b""


def api(*args):
    """bash 版の api() = `python3 "$here/anypoint-api.py" "$@" 2>"$err"`。
    (終了コード, 標準出力) を返す。標準出力の末尾の改行は $( ) と同じく落とす。"""
    r = subprocess.run([sys.executable, os.path.join(HERE, "anypoint-api.py")] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ERRBUF[:] = r.stderr
    return r.returncode, r.stdout.rstrip(b"\n")


def fail(code=1):
    """bash 版の fail() = `cat "$err" >&2; exit "${1:-1}"`。anypoint-api.py の終了コードをそのまま返す。"""
    errb(bytes(ERRBUF))
    sys.exit(code)


def usage():
    """上の「# 使い方:」から「# **apply」までのコメントをそのまま出す (元は sed -n で $0 を読んでいる)。"""
    lines, inside = [], False
    with open(os.path.abspath(__file__), "r", encoding="utf-8") as f:
        for ln in f.read().splitlines():
            if not inside:
                if re.search(r"^# 使い方:", ln):
                    inside = True
                    lines.append(ln)
            else:
                lines.append(ln)
                if re.search(r"^# \*\*apply", ln):
                    inside = False
    for ln in lines:                                   # sed 's/^# //; s/^#//'
        out(re.sub(r"^#", "", re.sub(r"^# ", "", ln, count=1), count=1))
    sys.exit(2)


def assets(q, limit="50"):
    """assets() { api "/exchange/api/v2/assets?types=policy&limit=${2:-50}&search=$1"; }"""
    return api("/exchange/api/v2/assets?types=policy&limit=%s&search=%s" % (limit, q))


def latest_version(a):
    """`assets "$a" 100 | jq -r '[.[] | select(.assetId == $a)][0].version // empty'` と同じ。
    `|| fail $?` はパイプライン末尾 (= jq) の終了コードなので、api が落ちても jq は空入力で 0 を返し、
    fail は呼ばれずに「見つからない」に落ちる (実測)。"""
    _, ob = assets(a, "100")
    if ob and loads(ob) is None:
        fail(5)                                        # jq のパースエラー (exit 5)
    for e in jq_iter(loads(ob)):
        if jq_get(e, "assetId") == a:
            return jq_empty(jq_get(e, "version"))
    return ""


def _resolve(a):
    """--- 共通: インスタンスを 1 件に決める ---"""
    if a == "" or any(c not in "0123456789" for c in a):     # case "$1" in ''|*[!0-9]*)
        rc, listb = api(AM + "?limit=100")
        if rc != 0:
            fail(rc)
        # jq: .assets[]? | .assetId as $asset | .apis[]? | select($asset == $a or .instanceLabel == $a)
        rows = []
        for asset in jq_iter(jq_get(loads(listb), "assets")):
            s = jq_get(asset, "assetId")
            for inst in jq_iter(jq_get(asset, "apis")):
                if s == a or jq_get(inst, "instanceLabel") == a:
                    rows.append((jq_tostring(jq_get(inst, "id")),
                                 jq_tostring(jq_alt(jq_get(inst, "instanceLabel"), "-")),
                                 jq_tostring(s)))
        ids = "\n".join(r[0] for r in rows)
        n = len([ln for ln in ids.split("\n") if ln != ""])   # printf '%s\n' "$ids" | grep -c .
        if not n >= 1:
            err("policy: '%s' という instanceLabel / assetId のインスタンスがこの環境に無い" % a)
            sys.exit(2)
        if n != 1:
            err("policy: '%s' に当たるインスタンスが %d 件。ID で指定する:" % (a, n))
            for i, lab, s in rows:
                err("  %s  %s  %s" % (i, lab, s))
            sys.exit(2)
        return ids
    return a


def cmd_find(argv):
    q = param_required(argv[0] if argv else None, "1", "使い方: policy.py find <語>   例: rate / jwt / client-id")
    rc, ob = assets(q)
    if rc != 0:
        fail(rc)
    o = loads(ob)
    if isinstance(o, list) or isinstance(o, dict):
        for e in sorted(jq_iter(o), key=lambda e: jq_sort_key(jq_get(e, "assetId"))):
            outb(bpad(jq_tostring(jq_get(e, "assetId")), 46) + b" "
                 + bpad(jq_tostring(jq_get(e, "version")), 12) + b" "
                 + jq_tostring(jq_alt(jq_get(e, "name"), "")).encode("utf-8") + b"\n")
    n = _jq_length(o)
    if not (n is not None and n > 0):
        err("policy: '%s' に当たるポリシーが無い (語を短く、英語で)" % q)
        sys.exit(1)
    out()
    out("設定キーを見る: python3 scripts/policy.py config <assetId>")


def _jq_length(o):
    """jq の length (null は 0、配列/オブジェクト/文字列は要素数)。数えられなければ None。"""
    if o is None:
        return 0
    if isinstance(o, (list, dict, str)):
        return len(o)
    return None


def cmd_config(argv):
    a = param_required(argv[0] if argv else None, "1", "使い方: policy.py config <assetId> [<version>]")
    v = argv[1] if len(argv) > 1 else ""
    if not v:
        v = latest_version(a)
        if not v:
            err("policy: ポリシー資産 '%s' が見つからない (python3 scripts/policy.py find <語> で探す)" % a)
            sys.exit(1)
    rc, detailb = api("/exchange/api/v2/assets/%s/%s/%s" % (EXCHANGE_POLICY_GROUP, a, v))
    if rc != 0:
        fail(rc)
    url = ""
    for f in jq_iter(jq_get(loads(detailb), "files")):     # jq '.files[]? | select(...) | .externalLink // empty' | head -1
        if jq_get(f, "classifier") == "schema" and jq_get(f, "packaging") == "json":
            e = jq_get(f, "externalLink")
            if e is None or e is False:
                continue                                   # // empty は行を出さないので head -1 に届かない
            url = jq_tostring(e)
            break
    if not url:
        err("policy: %s %s に設定スキーマ (schema.json) が無い" % (a, v))
        sys.exit(1)
    out("%s %s  (groupId %s)" % (a, v, EXCHANGE_POLICY_GROUP))
    # スキーマは if / then / else で「この値のときだけ要る項目」を表すことがあるので、その枝も出す
    _, sc = http(url, timeout=60)
    schema = loads(sc)

    def rows(src, req, tag):
        """jq の def rows($src; $req; $tag)。($src // {}) | to_entries[] ..."""
        src = jq_alt(src, {})
        if not isinstance(src, dict):
            raise JqError
        for k, val in src.items():
            t = jq_alt(jq_index(val, "type"), "?")
            need = "必須" if (isinstance(req, list) and k in req) else "任意"
            d = jq_alt(jq_alt(jq_index(val, "description"), jq_index(val, "title")), "")
            if not isinstance(d, str):
                raise JqError
            first = d.split("\n")[0] if d != "" else None   # jq: "" | split("\n") は [] なので [0] は null
            yield "%s%s\t%s\t%s\t%s" % (tag, k, jq_tostring(t), need, jq_tostring(first))

    try:
        for chunk in (rows(jq_index(schema, "properties"), jq_index(schema, "required"), ""),
                      rows(jq_index(jq_index(schema, "then"), "properties"),
                           jq_index(jq_index(schema, "then"), "required"), "(条件つき) "),
                      rows(jq_index(jq_index(schema, "else"), "properties"),
                           jq_index(jq_index(schema, "else"), "required"), "(条件つき) ")):
            for line in chunk:
                f = line.split("\t")
                outb(b"  " + bpad(f[0], 46) + b" " + bpad(f[1], 8) + b" " + bpad(f[2], 4) + b" "
                     + f[3].encode("utf-8")[:64] + b"\n")     # awk の substr($4,1,64) もバイト単位
    except JqError:
        pass                                                  # jq もここで止まり、以降の行は出ない
    consts = []
    try:
        for node in jq_recurse(schema):
            if isinstance(node, dict) and "oneOf" in node:
                for x in jq_iter(node["oneOf"]):
                    if isinstance(x, dict) and "const" in x:
                        consts.append(jq_tostring(x["const"]))
    except JqError:
        pass
    u = sorted(set(consts))
    if len(u) > 0:
        out("  選べる値: " + " / ".join(u))
    out()
    out("付ける: python3 scripts/policy.py apply <インスタンス> %s %s --config '{\"<キー>\": <値>}'" % (a, v))


def cmd_list(argv):
    api_id = subshell(lambda: _resolve(param_required(argv[0] if argv else None, "1",
                                                      "使い方: policy.py list <インスタンス>")))
    rc, ob = api(AM + "/" + api_id + "/policies")
    if rc != 0:
        fail(rc)
    o = loads(ob)
    for p in jq_iter(jq_get(o, "policies")):
        cfg = jq_get(p, "configuration")
        outb(bpad(jq_tostring(jq_get(p, "policyId")), 10) + b" "
             + bpad(jq_tostring(jq_get(p, "template", "assetId")), 34) + b" "
             + bpad(jq_tostring(jq_get(p, "template", "assetVersion")), 10) + b" "
             + bpad("order " + jq_tostring(jq_get(p, "order")), 9) + b" "
             + jq_tostring(cfg)[0:60].encode("utf-8") + b"\n")
    n = _jq_length(jq_get(o, "policies")) if isinstance(o, (dict, type(None))) else None
    out()
    out("%s 件。効いているかは表示ではなく bash scripts/policy-check.sh <URL> client-id <path> で決める"
        % ("" if n is None else n))


def cmd_apply_remove(verb, argv):
    # 許可の確認 (deploy-guard.sh と同じ形。ファイルを書き換えるのは人)
    root = os.getcwd()
    while root:
        if os.path.isfile(os.path.join(root, "context/deployment/authorizations.yaml")):
            break
        if os.path.exists(os.path.join(root, ".git")):
            root = ""
            break
        parent = os.path.dirname(root)
        if parent == root:
            root = ""
            break
        root = parent
    auth = (root + "/context/deployment/authorizations.yaml") if root else ""
    # sed -n '/^policy:/,/^[^ ]/p' | sed -n 's/^[[:space:]]*sandbox:[[:space:]]*\([a-z-]*\).*/\1/p' | head -1
    ok, inside = "", False
    for ln in (read_lines(auth) if auth else []):
        if not inside:
            if re.search(r"^policy:", ln):
                inside = True
            else:
                continue
        else:
            if re.search(r"^[^ ]", ln):
                inside = False
        m = re.match(r"^[ \t\r\f\v]*sandbox:[ \t\r\f\v]*([a-z-]*)", ln)
        if m:
            ok = m.group(1)
            break
    if ok != "allowed":
        err("policy: authorizations.yaml の policy.sandbox が '%s' なので %s はしない。" % (ok or "無し", verb))
        err("  許可を書くのは人 (%s)。**自分で書き換えない。**" % (auth or "context/deployment/authorizations.yaml"))
        err("  理由をそのまま人に伝えて止まる。")
        sys.exit(2)
    envname = os.environ.get("ANYPOINT_ENV") or ""
    if not envname:
        for ln in read_lines(os.path.join(root or ".", "context/deployment/sandbox.yaml")):
            m = re.match(r"^environment:[ \t\n\r\f\v]*([^#]*).*$", ln)
            if m:
                envname = m.group(1)
                break
    low = ascii_downcase(envname)
    if "prod" in low or "本番" in low:
        err("policy: 環境 '%s' は本番系。許可があっても止まる (本番は人が手で行う)" % envname)
        sys.exit(2)

    api_id = subshell(lambda: _resolve(param_required(argv[0] if argv else None, "1",
                                                      "使い方: policy.py %s <インスタンス> ..." % verb)))
    argv = argv[1:]                                    # shift (引数が無くても続く)
    rc, instb = api(AM + "/" + api_id)
    if rc != 0:
        fail(rc)
    inst = loads(instb)
    org = jq_tostring(jq_get(inst, "organizationId"))  # jq -r .organizationId (null なら "null")
    envid = jq_tostring(jq_get(inst, "environmentId"))
    host = os.environ.get("ANYPOINT_HOST") or "https://anypoint.mulesoft.com"
    # Secret はコマンド行に出さない (urllib の POST 本文なので argv にもプロセス一覧にも残らない)。
    # 環境変数が無いと printf の部分シェルだけが終わり、curl は空の本文を送る — 元の bash と同じ。
    body = subshell(lambda: '{"grant_type":"client_credentials","client_id":"%s","client_secret":"%s"}' % (
        param_required(os.environ.get("ANYPOINT_CLIENT_ID"), "ANYPOINT_CLIENT_ID", "環境変数が要る"),
        param_required(os.environ.get("ANYPOINT_CLIENT_SECRET"), "ANYPOINT_CLIENT_SECRET", "環境変数が要る")))
    _, tb = http(host + "/accounts/api/v2/oauth2/token", headers={"content-type": "application/json"},
                 data=body.encode("utf-8"), method="POST", timeout=30)
    tok = jq_empty(jq_get(loads(tb), "access_token"))
    if not tok:
        err("policy: トークンが取れない")
        sys.exit(2)
    B = "%s/apimanager/api/v1/organizations/%s/environments/%s/apis/%s/policies" % (host, org, envid, api_id)

    if verb == "remove":
        pid = param_required(argv[0] if argv else None, "1",
                             "使い方: policy.py remove <インスタンス> <policyId>   (policyId は list で見る)")
        code, ob = http(B + "/" + pid, headers={"Authorization": "Bearer " + tok}, method="DELETE", timeout=60)
        if code in ("204", "200"):
            out("policy: policyId %s を外した (HTTP %s)" % (pid, code))
        else:
            err("policy: 外せない (HTTP %s)" % code)
            errb(ob[:800])
            err()
            sys.exit(1)
        out("  守りが変わったので bash scripts/policy-check.sh <URL> ... を回し直す")
        sys.exit(0)

    a = param_required(argv[0] if argv else None, "1",
                       "使い方: policy.py apply <インスタンス> <assetId> [<version>] [--config '<JSON>'|@<file>]")
    argv = argv[1:]
    v = ""
    cfg = "{}"
    nxt = argv[0] if argv else ""
    if nxt == "--config" or nxt == "":
        pass
    else:
        v = nxt
        argv = argv[1:]
    if (argv[0] if argv else "") == "--config":
        c = param_required(argv[1] if len(argv) > 1 else None, "2", "--config の後に JSON か @<file>")
        if c.startswith("@"):
            cfg = _cat(c[1:])                          # cfg=$(cat "${c#@}")
        else:
            cfg = c
    parsed = json.loads(cfg) if cfg != "" else None     # printf '%s' "$cfg" | jq -e .
    try:
        parsed = json.loads(cfg)
    except Exception:
        parsed = None
    if cfg == "" or parsed is None or parsed is False:  # jq -e は null / false / 入力なし / パース失敗で非 0
        err("policy: --config が JSON ではない")
        sys.exit(2)
    if not v:
        v = latest_version(a)
        if not v:
            err("policy: ポリシー資産 '%s' が見つからない (python3 scripts/policy.py find <語>)" % a)
            sys.exit(1)
        err("policy: 版を省いたので Exchange の最新 %s を使う" % v)
    body = json.dumps({"groupId": EXCHANGE_POLICY_GROUP, "assetId": a, "assetVersion": v,
                       "configurationData": parsed}, indent=2, ensure_ascii=False)
    code, ob = http(B, headers={"Authorization": "Bearer " + tok, "content-type": "application/json"},
                    data=body.encode("utf-8"), method="POST", timeout=60)
    if code.startswith("2"):
        r = loads(ob)
        if r is None:
            pid, impl = "", ""                         # jq がパースに失敗したときは空
        else:
            pid = jq_tostring(jq_alt(jq_alt(jq_get(r, "id"), jq_get(r, "policyId")), "?"))
            ia = jq_get(r, "implementationAsset")
            impl = "%s %s (%s)" % (jq_tostring(jq_get(ia, "assetId")), jq_tostring(jq_get(ia, "version")),
                                   jq_tostring(jq_get(ia, "technology")))
        out("policy: %s %s を付けた。policyId %s / 実装 %s (HTTP %s)" % (a, v, pid, impl, code))
        out("  **付けただけでは守れているとは限らない。** bash scripts/policy-check.sh <URL> client-id <path> で実測する")
        out("  外す: python3 scripts/policy.py remove %s %s" % (api_id, pid))
    else:
        err("policy: 付けられない (HTTP %s)" % code)
        errb(ob[:1000])
        err()
        err("  設定キーが違うことが多い: python3 scripts/policy.py config %s %s で確かめる" % (a, v))
        err("  ゲートウェイが対応していないポリシーもある (technology が合うかはエラー本文に出る)")
        sys.exit(1)


def _cat(path):
    """cfg=$(cat "<file>")。読めなければ cat と同じ形の診断を出して空にする (末尾の改行は $( ) が落とす)。"""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read().rstrip("\n")
    except IsADirectoryError:
        err("cat: %s: Is a directory" % path)
    except OSError as e:
        err("cat: %s: %s" % (path, e.strerror))
    return ""


def main():
    argv = sys.argv[1:]
    verb = argv[0] if argv else ""
    argv = argv[1:]                                    # verb=${1:-}; shift || true
    if not verb:
        usage()
    if verb == "find":
        cmd_find(argv)
    elif verb == "config":
        cmd_config(argv)
    elif verb == "list":
        cmd_list(argv)
    elif verb in ("apply", "remove"):
        cmd_apply_remove(verb, argv)
    else:
        usage()


if __name__ == "__main__":
    main()
