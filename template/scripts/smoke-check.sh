#!/usr/bin/env bash
# デプロイ後の疎通確認。`samples/<resource>/<case>.in.json` を配置先に投げ、`<case>.out.json` と比べる。
#
# **サンプルの形は MUnit の入力です。HTTP のリクエストそのものではありません。**
#   in.json  : {"<uriParam>": 値, ..., "body": { 実際のリクエストボディ }}
#   out.json : {"status": 200, "body": { 実際の応答ボディ }}
# 受け入れ条件を作る段はこの形で作り、MUnit は `vars.sample.body` / `vars.sample.<uriParam>` を読みます。
#
# **v0.6.25 まで、このスクリプトはその形を知りませんでした。** ファイル全体を `--data-binary` で
# 送り (`{"inventoryId":3,"body":{...}}` がまるごとボディになる)、応答を out.json 全体と
# 比べていた (`{"status":...,"body":...}` と応答ボディが一致するはずがない)。status も見ていません
# でした。**つまり同じプラグインの中で 2 つのスキルがサンプルの形について食い違っていました。**
# 実測すると 2 プロジェクトとも同じ形なので、壊れていたのは両方です
# (台帳 inventory2-api: `.req.json` は method/path/headers しか上書きできず body の橋渡しが無い)。
#
# いまの動き:
#   ボディ  : in.json に `body` があればその中身だけを送る。無ければファイル全体 (後方互換)
#   期待値  : out.json に `status` と `body` があれば **status と body の両方**を比べる。
#             無ければファイル全体を応答ボディと比べる (後方互換)
#   method / path: **RAML から導きます** (`api/*.raml` の method と path を列挙し、
#             (1) path の末尾セグメントが case 名の先頭トークンと一致 (`reserve-ok` → `/.../reserve`)、
#             (2) path が resource ディレクトリ名を含む、(3) path の `{...}` と in.json の
#             トップレベルのキーが**完全一致** (集合の API と個別の API の取り違えを防ぐ)、
#             (4) body の有無が method と整合する — で選ぶ)。
#             **導けたかどうかは `--dry-run` で見えます。** 導けなければ `POST /<resource>` に落ちます。
#             上書きしたいときは `<case>.req.json` を隣に置く:
#     {"method":"PUT","path":"/inventory/{inventoryId}/reserve","headers":{"x-api-key":"..."}}
#     **`path` の `{...}` は in.json のトップレベルのキーで置き換わります** (`body` 以外)。
#     これが無いと、パス変数のある API は `.req.json` を書いても実際の URL を組めません。
#
# 結果は 1 ケース 1 行で knowledge/deploy-log.jsonl に残す。全部一致で exit 0、1 つでも違えば exit 1。
# `--dry-run <base>` で**何を送るつもりか**だけを出す (配備前に確かめられる)。
set -u
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
base=${1:?base-url}
mkdir -p knowledge
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fail=0; n=0

# RAML から case ごとの method / path を導いて表にする。**導けなくても止めない** (既定に落ちる)。
map=$(mktemp); trap 'rm -f "$map"' EXIT
python3 - > "$map" <<'PY' 2>/dev/null || true
import json, pathlib, re, sys
try:
    import yaml
except Exception:
    sys.exit(0)
class L(yaml.SafeLoader): pass
L.add_multi_constructor("!", lambda l, s, n: None)

eps = []   # (method, path, takes_body)
def walk(node, path):
    if not isinstance(node, dict): return
    for k, v in node.items():
        if isinstance(k, str) and k.startswith("/"):
            walk(v, path + k)
        elif k in ("get", "post", "put", "patch", "delete") and isinstance(v, dict):
            eps.append((k.upper(), path, isinstance(v.get("body"), dict)))
for r in sorted(pathlib.Path("api").glob("*.raml")) if pathlib.Path("api").is_dir() else []:
    try: walk(yaml.load(r.read_text(), Loader=L) or {}, "")
    except Exception: pass
if not eps: sys.exit(0)

for f in sorted(pathlib.Path("samples").glob("*/*.in.json")):
    res, case = f.parent.name, f.name[:-len(".in.json")]
    try: doc = json.loads(f.read_text())
    except Exception: continue
    keys = {k for k in doc if k not in ("body", "query")} if isinstance(doc, dict) else set()
    has_body = isinstance(doc, dict) and "body" in doc
    token = case.split("-")[0]
    best, score_best = None, 0
    for method, path, tb in eps:
        segs = [x for x in path.split("/") if x]
        params = {x[1:-1] for x in segs if x.startswith("{")}
        if not params <= keys: continue
        if has_body != tb: continue
        sc = 1
        if params == keys: sc += 3      # パス変数と in.json のキーが完全一致 (集合 vs 個別の取り違えを防ぐ)
        if segs and segs[-1] == token: sc += 2
        if res in segs: sc += 1
        if sc > score_best: best, score_best = (method, path), sc
    if best:
        print(f"{res}/{case}\t{best[0]}\t{best[1]}")
PY

for in in samples/*/*.in.json; do
  [ -f "$in" ] || continue
  n=$((n+1))
  res=$(dirname "$in"); res=${res#samples/}
  case=$(basename "$in" .in.json)
  out="${in%.in.json}.out.json"; req="${in%.in.json}.req.json"

  method=POST; path="/$res"; hdrs=(); src=既定
  if row=$(grep -m1 -P "^\Q$res/$case\E\t" "$map" 2>/dev/null); then
    method=$(printf '%s' "$row" | cut -f2); path=$(printf '%s' "$row" | cut -f3); src=RAML
  fi
  if [ -f "$req" ]; then
    src=req.json
    method=$(jq -r '.method // "POST"' "$req"); path=$(jq -r ".path // \"/$res\"" "$req")
    while IFS= read -r h; do hdrs+=(-H "$h"); done < <(jq -r '.headers // {} | to_entries[] | "\(.key): \(.value)"' "$req")
  fi
  # path の {キー} を in.json のトップレベルの値で置き換える (body は除く)
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && path=${path//\{$k\}/$v}
  done < <(jq -r 'to_entries[] | select(.key != "body" and .key != "query") | "\(.key)\t\(.value)"' "$in" 2>/dev/null)

  # in.json の `query` (検索系のサンプルはこの形) をクエリ文字列にする
  qs=$(jq -r 'if (.query? // empty) | type == "object" then (.query | to_entries | map("\(.key)=\(.value|tostring)") | join("&")) else "" end' "$in" 2>/dev/null)
  [ -n "${qs:-}" ] && path="$path?$qs"

  # ボディ: in.json に body があればその中身だけ
  reqbody=$(mktemp)
  if jq -e 'has("body")' "$in" >/dev/null 2>&1; then jq -c '.body' "$in" > "$reqbody"
  else cp "$in" "$reqbody"; fi

  if [ "$dry" = 1 ]; then
    printf '%-8s %-30s %-6s %s  (%s)\n' "dry-run" "$res/$case" "$method" "$base$path" "$src"
    [ "$method" != GET ] && echo "  body:     $(head -c 200 "$reqbody")"
    if jq -e 'has("status") and has("body")' "$out" >/dev/null 2>&1; then
      echo "  expected: status $(jq -r .status "$out") / body $(jq -c .body "$out" | head -c 160)"
    else
      echo "  expected: $(jq -c . "$out" 2>/dev/null | head -c 160)  (status を持たない古い形)"
    fi
    rm -f "$reqbody"; continue
  fi

  data=(); [ "$method" != GET ] && data=(-H 'content-type: application/json' --data-binary @"$reqbody")
  body=$(mktemp)
  code=$(curl -sS -m 30 -o "$body" -w '%{http_code}' -X "$method" "${hdrs[@]}" "${data[@]}" "$base$path" 2>/dev/null) || code=000

  if [ "$code" = 000 ]; then verdict=unreachable
  elif [ ! -f "$out" ]; then verdict=no-expected
  elif jq -e 'has("status") and has("body")' "$out" >/dev/null 2>&1; then
    want=$(jq -r .status "$out")
    if [ "$code" != "$want" ]; then verdict="status($code≠$want)"
    elif jq -e --slurpfile e <(jq -c .body "$out") '. == $e[0]' "$body" >/dev/null 2>&1; then verdict=match
    else verdict=mismatch; fi
  elif jq -e --slurpfile e "$out" '. == $e[0]' "$body" >/dev/null 2>&1; then verdict=match
  else verdict=mismatch; fi

  [ "$verdict" = match ] || fail=1
  printf '{"ts":"%s","event":"smoke","resource":"%s","case":"%s","status":%s,"verdict":"%s"}\n' \
    "$ts" "$res" "$case" "${code:-0}" "$verdict" >> knowledge/deploy-log.jsonl
  printf '%-14s %-30s %s %s\n' "$verdict" "$res/$case" "$method" "$code"
  if [ "$verdict" = mismatch ]; then
    echo "  expected: $(jq -c 'if has("status") and has("body") then .body else . end' "$out" 2>/dev/null | head -c 200)"
    echo "  actual:   $(head -c 200 "$body")"
  fi
  rm -f "$body" "$reqbody"
done
[ "$n" = 0 ] && { echo "smoke-check: samples/ にケースがありません" >&2; exit 2; }
exit $fail
