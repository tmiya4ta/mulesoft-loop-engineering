#!/usr/bin/env python3
"""デプロイ後の疎通確認。`samples/<resource>/<case>.in.json` を配置先に投げ、`<case>.out.json` と比べる。

**サンプルの形は MUnit の入力です。HTTP のリクエストそのものではありません。**
  in.json  : {"<uriParam>": 値, ..., "body": { 実際のリクエストボディ }}
  out.json : {"status": 200, "body": { 実際の応答ボディ }}
受け入れ条件を作る段はこの形で作り、MUnit は `vars.sample.body` / `vars.sample.<uriParam>` を読みます。

**v0.6.25 まで、このスクリプトはその形を知りませんでした。** ファイル全体を `--data-binary` で
送り (`{"inventoryId":3,"body":{...}}` がまるごとボディになる)、応答を out.json 全体と
比べていた (`{"status":...,"body":...}` と応答ボディが一致するはずがない)。status も見ていません
でした。**つまり同じプラグインの中で 2 つのスキルがサンプルの形について食い違っていました。**
実測すると 2 プロジェクトとも同じ形なので、壊れていたのは両方です
(台帳 inventory2-api: `.req.json` は method/path/headers しか上書きできず body の橋渡しが無い)。

いまの動き:
  ボディ  : in.json に `body` があればその中身だけを送る。無ければファイル全体 (後方互換)
  期待値  : out.json に `status` と `body` があれば **status と body の両方**を比べる。
            無ければファイル全体を応答ボディと比べる (後方互換)
  method / path: **RAML から導きます** (`api/*.raml` の method と path を列挙し、
            (1) path の末尾セグメントが case 名の先頭トークンと一致 (`reserve-ok` → `/.../reserve`)、
            (2) path が resource ディレクトリ名を含む、(3) path の `{...}` と in.json の
            トップレベルのキーが**完全一致** (集合の API と個別の API の取り違えを防ぐ)、
            (4) body の有無が method と整合する — で選ぶ)。
            **導けたかどうかは `--dry-run` で見えます。** 導けなければ `POST /<resource>` に落ちます。
            上書きしたいときは `<case>.req.json` を隣に置く:
  {"method":"PUT","path":"/inventory/{inventoryId}/reserve","headers":{"x-api-key":"..."}}
            **`path` の `{...}` は in.json のトップレベルのキーで置き換わります** (`body` 以外)。
            これが無いと、パス変数のある API は `.req.json` を書いても実際の URL を組めません。

結果は 1 ケース 1 行で knowledge/deploy-log.jsonl に残す。全部一致で exit 0、1 つでも違えば exit 1。
`--dry-run <base>` で**何を送るつもりか**だけを出す (配備前に確かめられる)。

v0.6.44 で bash + jq から Python にした。jq への依存を無くすためと、`grep -P` (GNU 限定。macOS の
BSD grep には無い) を使っていたため。**組み立てと判定の規則は変えていない**
(`--dry-run` の出力と、スタブサーバーに当てた判定が旧版と一致することを確かめた)。
"""
import json, os, pathlib, re, sys, time, urllib.error, urllib.request

argv = sys.argv[1:]
dry = False
if argv and argv[0] == "--dry-run":
    dry, argv = True, argv[1:]
if not argv:
    print("smoke-check: base-url が要ります", file=sys.stderr)
    sys.exit(2)
base = argv[0].rstrip("/")
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
METHODS = ("get", "post", "put", "patch", "delete")


def raml_files():
    d = pathlib.Path("api")
    return sorted(d.glob("*.raml")) if d.is_dir() else []


# RAML の baseUri のパス部分 (http://localhost:8081/api → /api) を base-url に**まだ付いていなければ**足す。
# base-url をホストだけで渡しても (https://app.cloudhub.io)、/api まで付けて渡しても動くようにする。
# 無条件に足すと、/api 付きで渡したときに /api/api になって全件 404 になる (実測: 利用者のプロジェクトで
# 「足さないと No listener for endpoint になる」と現地で直した版と、このスクリプトの説明が
# 「/api まで付けて渡す」だったのが重なって二重になった。inventory3-api T-006、2026-09-11)。
basepath = ""
for r in raml_files():
    m = re.search(r"^baseUri:\s*(\S+)", r.read_text(errors="ignore"), re.M)
    if m:
        basepath = re.sub(r"^[a-zA-Z]+://[^/]+", "", m.group(1).strip()).rstrip("/")
        break
if basepath and not base.endswith(basepath):
    base += basepath


# RAML から case ごとの method / path を導いて表にする。**導けなくても止めない** (既定に落ちる)。
def raml_map():
    try:
        import yaml
    except Exception:
        return {}

    class L(yaml.SafeLoader):
        pass
    L.add_multi_constructor("!", lambda l, s, n: None)

    eps = []   # (method, path, takes_body, query_param_names)

    def walk(node, path):
        if not isinstance(node, dict):
            return
        for k, v in node.items():
            if isinstance(k, str) and k.startswith("/"):
                walk(v, path + k)
            elif k in METHODS and isinstance(v, dict):
                qp = v.get("queryParameters") or {}
                names = [n.rstrip("?") for n in qp] if isinstance(qp, dict) else []
                eps.append((k.upper(), path, isinstance(v.get("body"), dict), names))

    for r in raml_files():
        try:
            walk(yaml.load(r.read_text(errors="ignore"), Loader=L) or {}, "")
        except Exception:
            pass
    if not eps:
        return {}

    out = {}
    for f in sorted(pathlib.Path("samples").glob("*/*.in.json")):
        res, case = f.parent.name, f.name[:-len(".in.json")]
        try:
            doc = json.loads(f.read_text(errors="ignore"))
        except Exception:
            continue
        keys = {k for k in doc if k not in ("body", "query")} if isinstance(doc, dict) else set()
        has_body = isinstance(doc, dict) and "body" in doc
        token = case.split("-")[0]
        best, score_best = None, 0
        for method, path, tb, qnames in eps:
            segs = [x for x in path.split("/") if x]
            params = {x[1:-1] for x in segs if x.startswith("{")}
            # トップレベルのキーのうち、この操作が宣言している queryParameters は「パス変数ではない」
            pkeys = keys - set(qnames)
            if not params <= pkeys:
                continue
            if has_body != tb:
                continue
            sc = 1
            if params == pkeys:
                sc += 3     # パス変数と in.json のキーが完全一致 (集合 vs 個別の取り違えを防ぐ)
            if segs and segs[-1] == token:
                sc += 2
            if res in segs:
                sc += 1
            if sc > score_best:
                best, score_best = (method, path, qnames), sc
        if best:
            out[f"{res}/{case}"] = best
    return out


MAP = raml_map()


def http(method, url, headers, body):
    req = urllib.request.Request(url, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    data = None
    if method != "GET" and body is not None:
        req.add_header("content-type", "application/json")
        data = body.encode()
    try:
        with urllib.request.urlopen(req, data, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception:
        return 0, ""


n = 0
fail = 0
pathlib.Path("knowledge").mkdir(exist_ok=True)
for inp in sorted(pathlib.Path("samples").glob("*/*.in.json")):
    n += 1
    res, case = inp.parent.name, inp.name[:-len(".in.json")]
    out_f = inp.with_name(case + ".out.json")
    req_f = inp.with_name(case + ".req.json")
    try:
        doc = json.loads(inp.read_text(errors="ignore"))
    except Exception:
        doc = {}
    if not isinstance(doc, dict):
        doc = {}

    method, path, src, qdecl, headers = "POST", f"/{res}", "既定", [], {}
    hit = MAP.get(f"{res}/{case}")
    if hit:
        method, path, qdecl = hit[0], hit[1], hit[2]
        src = "RAML"
    if req_f.is_file():
        src = "req.json"
        try:
            rq = json.loads(req_f.read_text(errors="ignore"))
        except Exception:
            rq = {}
        method = rq.get("method") or "POST"
        path = rq.get("path") or f"/{res}"
        headers = {str(k): str(v) for k, v in (rq.get("headers") or {}).items()}

    # path の {キー} を in.json のトップレベルの値で置き換える (body は除く)
    for k, v in doc.items():
        if k in ("body", "query"):
            continue
        path = path.replace("{" + k + "}", str(v))

    # in.json の `query` (検索系のサンプルはこの形) をクエリ文字列にする
    # **値が null のキーは送らない。** サンプルの null は「その検索条件を指定しない」の意味で、
    # そのまま送ると文字列 "null" で絞り込んでしまう (inventory3-api のサンプルで確認)。
    def s(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        return str(v)

    qs = ""
    q = doc.get("query")
    if isinstance(q, dict):
        qs = "&".join(f"{k}={s(v)}" for k, v in q.items() if v is not None)
    # **トップレベルのキーのうち、RAML がこの操作の queryParameters として宣言しているもの**もクエリにする。
    # MUnit は vars の名前に合わせてトップレベルに置くことが多く、入れ子の query だけを見ていると
    # 絞り込み無しで送ってしまう (inventory3-api T-006 で実測。回避のためにサンプルへ同じ値を
    # 二重に持たせていた)。宣言に無いキーは送らない (パス変数や MUnit 専用の値を混ぜないため)。
    for k, v in doc.items():
        if k not in qdecl or v is None or isinstance(v, (dict, list)):
            continue
        if re.search(r"(^|&)" + re.escape(k) + "=", qs):   # 入れ子の query を優先 (重複させない)
            continue
        qs = (qs + "&" if qs else "") + f"{k}={s(v)}"
    if qs:
        path = f"{path}?{qs}"

    # ボディ: in.json に body があればその中身だけ
    reqbody = json.dumps(doc["body"], ensure_ascii=False, separators=(",", ":")) if "body" in doc \
        else inp.read_text(errors="ignore")

    try:
        exp = json.loads(out_f.read_text(errors="ignore")) if out_f.is_file() else None
    except Exception:
        exp = None
    has_status = isinstance(exp, dict) and "status" in exp and "body" in exp

    if dry:
        print(f"{'dry-run':<8} {res + '/' + case:<30} {method:<6} {base}{path}  ({src})")
        if method != "GET":
            print(f"  body:     {reqbody[:200]}")
        if has_status:
            print(f"  expected: status {exp['status']} / body "
                  f"{json.dumps(exp['body'], ensure_ascii=False, separators=(',', ':'))[:160]}")
        else:
            body_s = json.dumps(exp, ensure_ascii=False, separators=(",", ":"))[:160] if exp is not None else ""
            print(f"  expected: {body_s}  (status を持たない古い形)")
        continue

    code, body = http(method, base + path, headers, reqbody)
    try:
        got = json.loads(body)
    except Exception:
        got = None

    if code == 0:
        verdict = "unreachable"
    elif exp is None:
        verdict = "no-expected"
    elif has_status:
        if str(code) != str(exp["status"]):
            verdict = f"status({code}≠{exp['status']})"
        else:
            verdict = "match" if got == exp["body"] else "mismatch"
    else:
        verdict = "match" if got == exp else "mismatch"

    if verdict != "match":
        fail = 1
    with open("knowledge/deploy-log.jsonl", "a", encoding="utf-8") as log:
        log.write(json.dumps({"ts": ts, "event": "smoke", "resource": res, "case": case,
                              "status": code, "verdict": verdict}, ensure_ascii=False) + "\n")
    print(f"{verdict:<14} {res + '/' + case:<30} {method} {code}")
    if verdict == "mismatch":
        want = exp["body"] if has_status else exp
        print(f"  expected: {json.dumps(want, ensure_ascii=False, separators=(',', ':'))[:200]}")
        print(f"  actual:   {body[:200]}")

if n == 0:
    print("smoke-check: samples/ にケースがありません", file=sys.stderr)
    sys.exit(2)
sys.exit(fail)
