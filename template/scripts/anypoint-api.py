#!/usr/bin/env python3
# Anypoint Platform API を **GET だけ**叩く共通の入口。トークン・組織 ID・環境 ID を解決して応答を出す。
#
# なぜ必要か。Anypoint にある値 (公開 URL、ゲートウェイの ID、インスタンスの状態) を、API で取れるのに
# 「分からない」と止まって人に画面を見てもらっていた (inventory3-api T-007、2026-09-11)。
# 叩くたびにトークン取得の curl を書き直し、Connected App の Secret をコマンド行に直接書いてもいた
# (会話の記録に残る)。ここに寄せれば Secret は環境変数から読むだけで、どこにも出ない。
#
# どの API のどのパスに目当ての値があるかは `python3 scripts/portal-search.py '<項目名>'` で引く。
# そこで出た行をそのまま流せば動く。
#
# 使い方:
#   python3 scripts/anypoint-api.py '/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways'
#   python3 scripts/anypoint-api.py '/apimanager/api/v1/organizations/{org}/environments/{env}/apis/<id>' | jq .deployment
#   python3 scripts/anypoint-api.py '<パス>' --find publicUrl     # 応答の中で名前に publicUrl を含む項目だけ出す
# パスの置き換え ({organizationId} / {environmentId} と書いても同じ):
#   {org} → 環境変数 ANYPOINT_ORG、無ければ pom.xml の groupId (組織 ID)
#   {env} → 環境変数 ANYPOINT_ENV、無ければ context/deployment/sandbox.yaml の environment (名前を ID に引く)
# 環境変数: ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET (Connected App)。
#           ANYPOINT_HOST (既定 https://anypoint.mulesoft.com。EU は https://eu1.anypoint.mulesoft.com)
#
# **書き込み (POST / PUT / PATCH / DELETE) はしない。** 調べるための道具です。変える操作はゴールの
# 手順と authorizations.yaml の許可に従い、専用のスクリプトで行う。
#
# exit 0 = 2xx (応答を標準出力。--find は当たった項目を `項目のパス = 値` で 1 行ずつ。当たらなければ exit 1)
#      1 = 2xx 以外 (状態と本文を標準エラー) / 2 = 前提が無い (資格情報、組織、環境、埋めていない変数)
#
# --- bash 版 (anypoint-api.py) からの移植メモ -------------------------------------------
# jq と curl への依存を外すのが目的なので、JSON は標準ライブラリの json、HTTP は urllib.request で行う。
# 元の `command -v jq || exit 2` (jq が無い) の検査は、jq を使わなくなったので消してある。
# curl は既定でリダイレクトを追わない (-L 無し) ので、urllib も追わない形にしてある (NoRedirect)。
import json
import os
import re
import sys
import urllib.error
import urllib.request


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


class JNum:
    """JSON の数を**元の字面のまま**持つ。jq 1.7 以降は数の字面を保つので `1.0` は `1.0` と出る。
    (指数表記の字面 1e10 だけは jq が 1E+10 に直すが、Anypoint の応答には出てこないので字面のまま出す)"""

    __slots__ = ("text",)

    def __init__(self, text):
        self.text = text

    def __str__(self):
        return self.text

    def __eq__(self, o):
        return isinstance(o, JNum) and self.text == o.text

    def __hash__(self):
        return hash(self.text)


def loads(b):
    """json.loads。数は JNum にして字面を保つ (jq と同じ見え方にするため)。失敗したら None。"""
    try:
        if isinstance(b, (bytes, bytearray)):
            b = b.decode("utf-8")
        return json.loads(b, parse_int=JNum, parse_float=JNum)
    except Exception:
        return None


def jq_tostring(v):
    """jq の `tostring` / 文字列補間 `\\(...)` と同じ形にする。"""
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


def ascii_downcase(s):
    """jq の ascii_downcase。A-Z だけを小さくする (非 ASCII は触らない)。"""
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """curl は -L 無しではリダイレクトを追わないので、urllib も追わない。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(NoRedirect)


def http(url, headers=None, data=None, method=None, timeout=30):
    """(HTTP の状態コードの文字列, 本文のバイト列) を返す。届かなければ ("000", b"")。
    curl -sS -o <file> -w '%{http_code}' と同じ (失敗は 000)。curl と違い、失敗の理由は標準エラーに出ない。"""
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


def read_lines(path):
    """sed / grep と同じく 1 行ずつ。無いファイルは空 (元も 2>/dev/null で握りつぶしている)。"""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except Exception:
        return []


def main():
    argv = sys.argv[1:]
    # p=${1:-}; shift || true
    p = argv[0] if argv else ""
    rest = argv[1:]
    find = ""
    # [ "${1:-}" = "--find" ] && find=${2:?--find の後に項目名}
    if (rest[0] if rest else "") == "--find":
        find = param_required(rest[1] if len(rest) > 1 else None, "2", "--find の後に項目名")
    # case "$p" in /*) ;; *) 使い方 ;; esac
    if not p.startswith("/"):
        err("使い方: anypoint-api.py '/<API のパス>' [--find <項目名>]   (ホスト名は付けない。例: /accounts/api/me)")
        sys.exit(2)
    host = os.environ.get("ANYPOINT_HOST") or "https://anypoint.mulesoft.com"
    if not os.environ.get("ANYPOINT_CLIENT_ID") or not os.environ.get("ANYPOINT_CLIENT_SECRET"):
        err("anypoint-api: 環境変数 ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET が無い。")
        err("  Claude Code の Bash は毎回新しいシェルなので、人に「export してから claude を起動し直す」を頼む。")
        err("  **値を会話・コマンド行・台帳・ファイルに書かない。** 会話で渡されても export ...=<値> と打たずに頼む")
        err("  (ファイルに書くと /mule-run の git add -A でコミットに入ることがある)。")
        sys.exit(2)

    # Secret をコマンド行に出さない (本体は urllib の POST 本文として渡すので、argv にもプロセス一覧にも残らない)
    body = ('{"grant_type":"client_credentials","client_id":"%s","client_secret":"%s"}'
            % (os.environ["ANYPOINT_CLIENT_ID"], os.environ["ANYPOINT_CLIENT_SECRET"])).encode("utf-8")
    _, tokbody = http(host + "/accounts/api/v2/oauth2/token",
                      headers={"content-type": "application/json"},
                      data=body, method="POST", timeout=30)
    j = loads(tokbody)
    tok = j.get("access_token") if isinstance(j, dict) else None
    tok = "" if tok is None or tok is False else jq_tostring(tok)   # jq -r '.access_token // empty'
    if not tok:
        err("anypoint-api: トークンが取れない (Connected App の ID / Secret か、ANYPOINT_HOST の地域を確かめる)")
        sys.exit(2)
    auth = {"Authorization": "Bearer " + tok}

    for a, b in (("{organizationId}", "{org}"), ("{orgId}", "{org}"),
                 ("{environmentId}", "{env}"), ("{envId}", "{env}")):
        p = p.replace(a, b)
    org = os.environ.get("ANYPOINT_ORG") or ""
    if not org:
        # sed -n 's/.*<groupId>\([0-9a-f-]\{36\}\)<\/groupId>.*/\1/p' pom.xml | head -1
        for line in read_lines("pom.xml"):
            m = re.match(r".*<groupId>([0-9a-f-]{36})</groupId>", line)
            if m:
                org = m.group(1)
                break
    if "{org}" in p or "{env}" in p:
        if not org:
            err("anypoint-api: 組織 ID が分からない (pom.xml の groupId が組織 ID でない)。ANYPOINT_ORG=<組織 ID> で渡す")
            sys.exit(2)
    envid = None
    if "{env}" in p:
        en = os.environ.get("ANYPOINT_ENV") or ""
        if not en:
            # sed -n 's/^environment:[[:space:]]*\([^#]*\).*/\1/p' context/deployment/sandbox.yaml | head -1
            for line in read_lines("context/deployment/sandbox.yaml"):
                m = re.match(r"^environment:[ \t\n\r\f\v]*([^#]*).*$", line)
                if m:
                    en = m.group(1)
                    break
        # sed 's/[[:space:]]*$//; s/^"\(.*\)"$/\1/'
        en = "\n".join(re.sub(r'^"(.*)"$', r"\1", re.sub(r"[ \t\r\f\v]*$", "", ln))
                       for ln in en.split("\n")).rstrip("\n")
        if not en:
            err("anypoint-api: 環境名が分からない。ANYPOINT_ENV=<環境名> で渡すか、sandbox.yaml の environment を人に埋めてもらう")
            sys.exit(2)
        if any(re.fullmatch(r"[0-9a-f-]{36}", ln) for ln in en.split("\n")):
            envid = en
        else:
            _, eb = http("%s/accounts/api/organizations/%s/environments" % (host, org), headers=auth, timeout=30)
            ej = loads(eb)
            envid = ""
            data = ej.get("data") if isinstance(ej, dict) else None
            if isinstance(data, list):
                for e in data:                       # jq '.data[]? | select(.name == $n) | .id' | head -1
                    if isinstance(e, dict) and e.get("name") == en:
                        v = e.get("id")
                        envid = "" if v is None or v is False else jq_tostring(v)
                        break
        if not envid:
            err("anypoint-api: 環境 '%s' が組織 %s に無い (名前は大文字小文字まで一致させる)" % (en, org))
            sys.exit(2)
        p = p.replace("{env}", envid)
    if org:
        p = p.replace("{org}", org)
    if re.search(r"\{.*\}", p, re.S):
        got = re.findall(r"\{[^}]*\}", p)
        err("anypoint-api: パスに埋めていない変数がある: " + ("".join(g + " " for g in got)))
        err("  その値は、同じ API の一覧の操作で取る (portal-search.py の「の値」の行に書いてある)")
        sys.exit(2)

    hdr = dict(auth)
    if org:
        hdr["X-ANYPNT-ORG-ID"] = org
    if envid:
        hdr["X-ANYPNT-ENV-ID"] = envid
    code, out_bytes = http(host + p, headers=hdr, timeout=60)
    if not code.startswith("2"):
        err("anypoint-api: GET %s → HTTP %s" % (p, code))
        errb(out_bytes[:1500])        # head -c 1500
        err()
        if code in ("401", "403"):
            err("  Connected App にこの API のスコープが無い。足すのは人 (組織管理者)。どのスコープかは portal-search.py の仕様の description にある")
        elif code == "404":
            err("  パスか ID が違う。ID は一覧の操作 (list...) で取り直す。組織・環境が違うこともある")
        elif code == "000":
            err("  %s に届かない (ネットワーク、または ANYPOINT_HOST の地域)" % host)
        sys.exit(1)
    if not find:
        outb(out_bytes)               # cat "$out"
        out()                         # echo
        sys.exit(0)

    # jq: paths(scalars) のうち、パスのどこかの要素名に語を含むものを `パスのドット表記 = 値` で出す。
    # select() は null / false を偽とみなすので、値が null か false の項目は jq でも落ちる (実測)。
    hits = []
    doc = loads(out_bytes)
    if doc is not None:
        w = ascii_downcase(find)
        for path, val in _paths_scalars(doc):
            if val is None or val is False:
                continue
            if any(w in ascii_downcase(str(c)) for c in path):
                hits.append("%s = %s" % (".".join(str(c) for c in path), jq_tostring(val)))
    if not hits:
        err("anypoint-api: 応答に '%s' を名前に含む項目は無い (応答全体は --find を外して見る)" % find)
        sys.exit(1)
    out("\n".join(hits))


def _paths_scalars(v, cur=()):
    """jq の paths(scalars)。深さ優先・文書順。空の配列/オブジェクトは葉ではないので出ない。"""
    if isinstance(v, dict):
        for k, x in v.items():
            yield from _paths_scalars(x, cur + (k,))
    elif isinstance(v, list):
        for i, x in enumerate(v):
            yield from _paths_scalars(x, cur + (i,))
    elif cur:
        yield cur, v


if __name__ == "__main__":
    main()
