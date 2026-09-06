#!/usr/bin/env bash
# policy 段の done_when。<base-url> に認証なしで叩いて 401/403、認証ありで 2xx なら exit 0。
# 使い方: policy-check.sh <base-url> client-id   (環境変数 CLIENT_ID / CLIENT_SECRET)
#         policy-check.sh <base-url> jwt         (環境変数 JWT)
#         policy-check.sh <base-url> none        (認証なしで 2xx なら exit 0)
set -u
base=${1:?base-url}; kind=${2:-client-id}
path=$(ls samples/*/*.req.json 2>/dev/null | head -1 | xargs -r jq -r '.path // empty'); path=${path:-/}
code() { curl -sS -m 30 -o /dev/null -w '%{http_code}' "$@" "$base$path" 2>/dev/null || echo 000; }
no=$(code)
case "$kind" in
  client-id) yes=$(code -H "client_id: ${CLIENT_ID:?}" -H "client_secret: ${CLIENT_SECRET:?}") ;;
  jwt)       yes=$(code -H "Authorization: Bearer ${JWT:?}") ;;
  none)      yes=$no; no=401 ;;
  *) echo "policy-check: kind は client-id | jwt | none" >&2; exit 2 ;;
esac
echo "policy-check: without auth=$no, with auth=$yes ($kind, $path)"
case "$no" in 401|403) ;; *) echo "policy-check: 認証なしで $no が返る (ポリシーが効いていない)" >&2; exit 1 ;; esac
case "$yes" in 2*) exit 0 ;; *) echo "policy-check: 認証ありで $yes が返る" >&2; exit 1 ;; esac
