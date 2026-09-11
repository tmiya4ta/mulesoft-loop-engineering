#!/usr/bin/env bash
# policy 段の done_when。<base-url> に認証なしで叩いて 401/403、認証ありで 2xx なら exit 0。
# 使い方: policy-check.sh <base-url> client-id [<path>]   (環境変数 CLIENT_ID / CLIENT_SECRET)
#         policy-check.sh <base-url> jwt [<path>]         (環境変数 JWT)
#         policy-check.sh <base-url> none [<path>]        (認証なしで 2xx なら exit 0)
# <base-url> は Flex Gateway なら `bash scripts/gateway-public-url.sh <インスタンス>` が出したもの。
# <path> は GET して 2xx が返るリソース (例 /inventory)。省くと、GET で変数の無い `*.req.json` の path、
# 無ければ `/`。**v0.6.40 までは最初の `*.req.json` をそのまま GET していた**ので、
# `PUT /inventory/{inventoryId}/reserve` が選ばれ、ポリシーが効いていても認証ありで 405 になって落ちた
# (inventory3-api T-007、2026-09-12)。
set -u
base=${1:?base-url}; kind=${2:-client-id}; path=${3:-}
if [ -z "$path" ]; then
  for f in samples/*/*.req.json; do
    [ -f "$f" ] || continue
    m=$(jq -r '.method // "GET"' "$f" | tr '[:lower:]' '[:upper:]'); pp=$(jq -r '.path // empty' "$f")
    case "$m:$pp" in GET:/*) case "$pp" in *'{'*) ;; *) path=$pp; break ;; esac ;; esac
  done
fi
path=${path:-/}
code() { curl -sS -m 30 -o /dev/null -w '%{http_code}' "$@" "$base$path" 2>/dev/null || echo 000; }
no=$(code)
case "$kind" in
  client-id) yes=$(code -H "client_id: ${CLIENT_ID:?}" -H "client_secret: ${CLIENT_SECRET:?}") ;;
  jwt)       yes=$(code -H "Authorization: Bearer ${JWT:?}") ;;
  none)      yes=$no; no=401 ;;
  *) echo "policy-check: kind は client-id | jwt | none" >&2; exit 2 ;;
esac
echo "policy-check: without auth=$no, with auth=$yes ($kind, $path)"
case "$no" in
  401|403) ;;
  404) echo "policy-check: 認証なしで 404 — その URL にはゲートウェイの経路が無い (base-url が違う)。" >&2
       echo "  Flex Gateway なら bash scripts/gateway-public-url.sh <インスタンス> で取り直す" >&2; exit 1 ;;
  *) echo "policy-check: 認証なしで $no が返る (ポリシーが効いていない)" >&2; exit 1 ;;
esac
case "$yes" in
  2*) exit 0 ;;
  401|403) echo "policy-check: 認証ありでも $yes — その資格情報はこの API インスタンスと契約していない。" >&2
           echo "  契約の有無: bash scripts/anypoint-api.sh '/apimanager/api/v1/organizations/{org}/environments/{env}/apis/<インスタンス ID>/contracts'" >&2
           echo "  無ければ利用者アプリを作って契約する (knowledge/gotchas/api-manager.md の「利用者アプリの作成」)" >&2; exit 1 ;;
  404|405) echo "policy-check: 認証ありで $yes — ポリシーは通ったが、path $path は GET できない。" >&2
           echo "  GET して 2xx が返るリソースを 3 つ目に渡す (例: policy-check.sh $base $kind /inventory)" >&2; exit 1 ;;
  *) echo "policy-check: 認証ありで $yes が返る" >&2; exit 1 ;;
esac
