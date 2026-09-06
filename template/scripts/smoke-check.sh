#!/usr/bin/env bash
# デプロイ後の疎通確認。samples/<resource>/<case>.in.json を配置先に投げ、応答を <case>.out.json と比較する。
# 使い方: smoke-check.sh <base-url>   例: smoke-check.sh https://order-sapi-abc.us-e2.cloudhub.io/api
# 要求の形は既定で POST /<resource> (body = in.json)。違うときは <case>.req.json を隣に置く:
#   {"method":"GET","path":"/orders/123","headers":{"x-api-key":"..."}}
# 結果は 1 ケース 1 行で knowledge/deploy-log.jsonl に残す。全部一致で exit 0、1 つでも違えば exit 1。
set -u
base=${1:?base-url}
mkdir -p knowledge
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fail=0; n=0
for in in samples/*/*.in.json; do
  [ -f "$in" ] || continue
  n=$((n+1))
  res=$(dirname "$in"); res=${res#samples/}
  case=$(basename "$in" .in.json)
  out="${in%.in.json}.out.json"; req="${in%.in.json}.req.json"
  method=POST; path="/$res"; hdrs=()
  if [ -f "$req" ]; then
    method=$(jq -r '.method // "POST"' "$req"); path=$(jq -r ".path // \"/$res\"" "$req")
    while IFS= read -r h; do hdrs+=(-H "$h"); done < <(jq -r '.headers // {} | to_entries[] | "\(.key): \(.value)"' "$req")
  fi
  data=(); [ "$method" != GET ] && data=(-H 'content-type: application/json' --data-binary @"$in")
  body=$(mktemp)
  code=$(curl -sS -m 30 -o "$body" -w '%{http_code}' -X "$method" "${hdrs[@]}" "${data[@]}" "$base$path" 2>/dev/null) || code=000
  if [ "$code" = 000 ]; then verdict=unreachable
  elif [ -f "$out" ] && jq -e --slurpfile e "$out" '. == $e[0]' "$body" >/dev/null 2>&1; then verdict=match
  else verdict=mismatch; fi
  [ "$verdict" = match ] || fail=1
  printf '{"ts":"%s","event":"smoke","resource":"%s","case":"%s","status":%s,"verdict":"%s"}\n' \
    "$ts" "$res" "$case" "${code:-0}" "$verdict" >> knowledge/deploy-log.jsonl
  printf '%-8s %-30s %s %s\n' "$verdict" "$res/$case" "$method" "$code"
  [ "$verdict" = mismatch ] && { echo "  expected: $(jq -c . "$out" 2>/dev/null | head -c 200)"; echo "  actual:   $(head -c 200 "$body")"; }
  rm -f "$body"
done
[ "$n" = 0 ] && { echo "smoke-check: samples/ にケースがありません" >&2; exit 2; }
exit $fail
