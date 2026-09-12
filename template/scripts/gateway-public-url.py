#!/usr/bin/env python3
# Managed Flex Gateway (Omni Gateway) に置いた API インスタンスの、**外から叩ける URL** を出す。
#
# なぜ必要か。API Manager のインスタンスには upstream (`endpoint.uri`) とゲートウェイ内の待ち受け
# (`endpoint.proxyUri`、例 `http://0.0.0.0:8081/inventory3-api/`) しか無く、外からの URL はどこにも
# 書かれていない。それで「API から取れない」と【未解決】にして人に画面を見てもらっていた
# (inventory3-api T-007、2026-09-11)。**実際はゲートウェイの側** (Gateway Manager API の getGatewayById) にある:
#   configuration.ingress.publicUrl / endpoints[]   ゲートウェイの公開 URL (例 https://ft1-xxxxxx.<dnsTarget>)
#   portConfiguration.ingress.port                  公開 URL が届く港 (例 8081)
#   portConfiguration.egress.port                   Private Space の内側からだけ届く港 (例 8082)
# **API の URL = 公開 URL + proxyUri のパス。proxyUri の港が ingress の港のときだけ外から届く。**
#
# 実測 (ft1、2026-09-12): `/inventory3-api/inventory` は 401 (client-id ポリシーが応答)、
# `/inventory3-api` (末尾の / 無し) とゲートウェイに無いパスは 404、egress (8082) に置いた API を
# 公開 URL で叩くと 404。self-managed のゲートウェイ (kind: selfManaged) は Gateway Manager に無く 404。
#
# 使い方: python3 scripts/gateway-public-url.py <API インスタンス ID | instanceLabel | assetId>
#   標準出力: 外から叩く base URL。**末尾の / は付けない。後ろにリソース (/inventory など) を付けて使う**
#             (base だけを叩くと 404 になるのは正常)。policy-check.sh の 1 つ目にそのまま渡せる
#   標準エラー: 内側の URL、upstream、ゲートウェイを迂回できる恐れ
# 環境変数と組織・環境の解決は anypoint-api.py と同じ (ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)。
#
# exit 0 = 出した / 1 = 外からの URL が無い (egress の港に置いた、self-managed、公開 URL 未設定)
#      2 = 前提が無い (資格情報、未配備、flexGateway でない、候補が複数)
#
# --- bash 版 (gateway-public-url.py) からの移植メモ ---------------------------------------
# jq と curl への依存を外すのが目的なので、JSON は標準ライブラリの json、HTTP は urllib.request で行う。
# 元の `api()` (python3 scripts/anypoint-api.py を呼んで標準エラーを $err に溜める) は、同じディレクトリの
# anypoint-api.py を sys.executable で呼ぶ形にしてある (呼ばれる側は単体でも CLI として動く)。
# $err は mktemp のファイルだったが、中身を見るのはこのスクリプトだけなので bytearray にしてある。
import fnmatch
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))     # here=$(cd "$(dirname "$0")" && pwd)
ERRBUF = bytearray()                                  # err=$(mktemp)
AM = "/apimanager/api/v1/organizations/{org}/environments/{env}/apis"


# --- bash の細かい意味を写す道具 --------------------------------------------------------
def out(s=""):
    sys.stdout.buffer.write(s.encode("utf-8") + b"\n")
    sys.stdout.flush()


def err(s=""):
    sys.stdout.flush()
    sys.stderr.buffer.write(s.encode("utf-8") + b"\n")
    sys.stderr.flush()


def param_required(value, param, msg):
    """bash の ${N:?msg}。未設定か空なら診断を出して exit 1 (bash と同じ形・同じ終了コード)。"""
    if value is None or value == "":
        err("%s: line %d: %s: %s" % (sys.argv[0], sys._getframe(1).f_lineno, param, msg))
        sys.exit(1)
    return value


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


def loads(b):
    """json.loads。数は JNum にして字面を保つ。失敗したら None (jq がエラーで何も出さないのと同じ)。"""
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
    """jq の .a.b.c。null を辿ると null。オブジェクト以外を辿ったら jq はエラーになるが、ここは None。"""
    for k in keys:
        if o is None:
            return None
        if not isinstance(o, dict):
            return None
        o = o.get(k)
    return o


def jq_iter(v):
    """jq の .[]? 。配列はそのまま、オブジェクトは値、それ以外は何も出さない。"""
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return list(v.values())
    return []


def jq_empty(o, *keys):
    """jq -r '.a.b // empty' と同じ。null / false なら空文字。"""
    v = jq_get(o, *keys)
    return "" if v is None or v is False else jq_tostring(v)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """curl は -L 無しではリダイレクトを追わないので、urllib も追わない。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(NoRedirect)


def http_code(url, timeout):
    """curl -sS -o /dev/null -w '%{http_code}' と同じ。届かなければ "000"。
    curl と違い、届かない理由は標準エラーに出ない (元も 2>/dev/null で捨てている)。"""
    try:
        with _opener.open(urllib.request.Request(url), timeout=timeout) as r:
            r.read()
            return str(r.status)
    except urllib.error.HTTPError as e:
        try:
            e.read()
        except Exception:
            pass
        return str(e.code)
    except Exception:
        return "000"


def api(*args):
    """bash 版の api() = `python3 "$here/anypoint-api.py" "$@" 2>"$err"`。
    (終了コード, 標準出力) を返す。標準出力の末尾の改行は $( ) と同じく落とす。"""
    r = subprocess.run([sys.executable, os.path.join(HERE, "anypoint-api.py")] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ERRBUF[:] = r.stderr
    return r.returncode, r.stdout.rstrip(b"\n")


def fail():
    """bash 版の fail() = `cat "$err" >&2; exit 2`。"""
    sys.stdout.flush()
    sys.stderr.buffer.write(bytes(ERRBUF))
    sys.stderr.flush()
    sys.exit(2)


def read2(line):
    """IFS=<TAB> read -r u pr。タブは IFS の空白なので前後は捨て、連続は 1 つの区切りにする。"""
    s = line.strip("\t")
    if not s:
        return "", ""
    parts = re.split(r"\t+", s, maxsplit=1)
    return parts[0], (parts[1] if len(parts) > 1 else "")


def main():
    arg = param_required(sys.argv[1] if len(sys.argv) > 1 else None, "1",
                         "使い方: gateway-public-url.py <API インスタンス ID | instanceLabel | assetId>")

    if any(c not in "0123456789" for c in arg):        # case "$arg" in *[!0-9]*)
        rc, listb = api(AM + "?limit=100")
        if rc != 0:
            fail()
        lst = loads(listb)
        # jq: .assets[]? | .assetId as $asset | .apis[]? | select($asset == $a or .instanceLabel == $a)
        rows = []                                      # (id, instanceLabel, assetId)
        for asset in jq_iter(jq_get(lst, "assets")):
            a = jq_get(asset, "assetId")
            for inst in jq_iter(jq_get(asset, "apis")):
                if a == arg or jq_get(inst, "instanceLabel") == arg:
                    lab = jq_get(inst, "instanceLabel")
                    rows.append((jq_tostring(jq_get(inst, "id")),
                                 "-" if lab is None or lab is False else jq_tostring(lab),
                                 jq_tostring(a)))
        ids = "\n".join(r[0] for r in rows)
        n = len([ln for ln in ids.split("\n") if ln != ""])     # printf '%s\n' "$ids" | grep -c .
        if not n >= 1:
            err("gateway-public-url: '%s' という instanceLabel / assetId のインスタンスがこの環境に無い" % arg)
            sys.exit(2)
        if n > 1:
            err("gateway-public-url: '%s' に当たるインスタンスが %d 件。ID で指定する:" % (arg, n))
            for i, lab, a in rows:
                err("  %s  %s  %s" % (i, lab, a))
            sys.exit(2)
        api_id = ids
    else:
        api_id = arg

    rc, instb = api(AM + "/" + api_id)
    if rc != 0:
        fail()
    inst = loads(instb)
    tech = jq_empty(inst, "technology")
    gw = jq_empty(inst, "deployment", "targetId")
    gwname = jq_empty(inst, "deployment", "targetName")
    proxy = jq_empty(inst, "endpoint", "proxyUri")
    up = jq_empty(inst, "endpoint", "uri")
    if tech != "flexGateway":
        err("gateway-public-url: インスタンス %s の technology は '%s' (flexGateway ではない)。対象外" % (api_id, tech))
        sys.exit(2)
    if not gw:
        err("gateway-public-url: インスタンス %s はまだどのゲートウェイにも配備されていない (deployment が空)" % api_id)
        sys.exit(2)
    if not proxy:
        err("gateway-public-url: インスタンス %s に endpoint.proxyUri が無い" % api_id)
        sys.exit(2)

    rc, gb = api("/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways/" + gw)
    if rc != 0:
        if b"HTTP 404" in ERRBUF:                      # grep -q 'HTTP 404' "$err"
            err("gateway-public-url: ゲートウェイ %s は Gateway Manager に無い = self-managed。" % gwname)
            err("  外からの URL は、それを動かしている側 (人) が決める。ゲートウェイ内の待ち受けは %s" % proxy)
            sys.exit(1)
        fail()
    g = loads(gb)

    m = re.match(r"^[a-z]*://[^/:]*:([0-9][0-9]*)", proxy)
    port = m.group(1) if m else ""
    m = re.match(r"^[a-z]*://[^/]*(/.*)$", proxy)
    path = m.group(1) if m else ""
    path = path[:-1] if path.endswith("/") else path   # path=${path%/}
    ingress = jq_empty(g, "portConfiguration", "ingress", "port")
    egress = jq_empty(g, "portConfiguration", "egress", "port")
    if ingress and port and port != ingress:
        if port == egress:
            cluster = re.sub(r"/$", "", jq_empty(g, "clusterUrl"))
            err("gateway-public-url: この API は egress の港 (%s) に置かれている。外からの URL は無い。" % egress)
            err("  Private Space の内側から %s%s でだけ届く。" % (cluster, path))
            err("  外から叩きたいなら proxyUri を港 %s で作り直す。" % ingress)
        else:
            err("gateway-public-url: proxyUri の港 %s は、ゲートウェイの ingress (%s) でも egress (%s) でもない"
                % (port, ingress, egress))
        sys.exit(1)

    # endpoints[] (access と pathRewrite 付き) を優先。無ければ publicUrl / internalUrl (カンマ区切り) を使う
    def urls(access):
        """<external|internal> → "URL<TAB>pathRewrite" を 1 行ずつ"""
        i = jq_get(g, "configuration", "ingress")
        e = []
        for x in jq_iter(jq_get(i, "endpoints")):
            if jq_get(x, "access") == access:
                pr = jq_get(x, "pathRewrite")
                pr = "/" if pr is None or pr is False else pr
                e.append("%s\t%s" % (jq_tostring(jq_get(x, "url")), jq_tostring(pr)))
        if len(e) > 0:
            return e
        v = jq_get(i, "publicUrl" if access == "external" else "internalUrl")
        v = "" if v is None or v is False else v
        if not isinstance(v, str):
            return []                                  # jq なら split でエラーになるところ
        return ["%s\t/" % s for s in v.split(",") if len(s) > 0]

    def build(u, pr):
        """<url> <pathRewrite> → 外からの URL。届かないなら None"""
        u = u[:-1] if u.endswith("/") else u           # u=${1%/}
        pr = pr[:-1] if pr.endswith("/") else pr       # pr=${2%/}
        if path == pr or path.startswith(pr + "/"):
            return u + path[len(pr):]
        return None

    result = ""
    for line in urls("external"):
        u, pr = read2(line)
        if not u:
            continue
        r = build(u, pr)
        if r is None:
            err("  (公開 URL %s は pathRewrite %s なので %s には届かない)" % (u, pr, path))
            continue
        if not result:
            result = r
        else:
            err("  別の公開 URL: %s" % r)
    if not result:
        err("gateway-public-url: ゲートウェイ %s に公開 URL が設定されていない (configuration.ingress)" % gwname)
        sys.exit(1)

    for line in urls("internal"):
        u, pr = read2(line)
        if u:
            r = build(u, pr)
            if r is not None:
                err("  内側の URL (同じ Private Space から): %s" % r)
    err("  ゲートウェイ %s / 待ち受け %s / upstream %s" % (gwname, proxy, up))
    # upstream が外から直接届くなら、ゲートウェイを迂回してポリシーを素通りできる
    if not (up == "" or fnmatch.fnmatchcase(up, "http*://*internal*")):
        c = http_code(up, timeout=10)
        if c != "000":
            err("  **注意**: upstream %s に外から直接届く (HTTP %s)。ゲートウェイを迂回すればポリシーは効かない。" % (up, c))
            err("  Proxy 型では upstream をアプリの内部 URL にし、アプリの公開 URL を消す (knowledge/gotchas/api-manager.md)。")
    out(result)


if __name__ == "__main__":
    main()
