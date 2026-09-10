#!/usr/bin/env bash
# CloudHub 2.0 のアプリに既定の公開 URL を付けて表示する。
# `runtime-mgr application modify --publicEndpoints` は効かない (knowledge/gotchas/deploy.md)。
# Application Manager の API で deploymentSettings.generateDefaultPublicUrl を立てる。
# 使い方: ch2-public-url.sh <app-name> <environment-name>   (環境変数 ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)
set -eu
app=${1:?app-name}; envname=${2:?environment-name}
host=https://anypoint.mulesoft.com
org=$(sed -n 's/.*<groupId>\([0-9a-f-]\{36\}\)<\/groupId>.*/\1/p' pom.xml | head -1)
[ -n "$org" ] || { echo "ch2-public-url: pom の groupId が組織 ID ではありません" >&2; exit 2; }
tok=$(curl -sS -X POST "$host/accounts/api/v2/oauth2/token" -H 'content-type: application/json' \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"${ANYPOINT_CLIENT_ID:?}\",\"client_secret\":\"${ANYPOINT_CLIENT_SECRET:?}\"}" | jq -r .access_token)
[ "$tok" != null ] && [ -n "$tok" ] || { echo "ch2-public-url: トークン取得に失敗 (Connected App の権限を確認)" >&2; exit 2; }
H=(-H "Authorization: Bearer $tok" -H 'content-type: application/json')
env=$(curl -sS "${H[@]}" "$host/accounts/api/organizations/$org/environments" | jq -r --arg n "$envname" '.data[] | select(.name==$n) | .id')
[ -n "$env" ] || { echo "ch2-public-url: 環境 $envname が見つかりません" >&2; exit 2; }
base="$host/amc/application-manager/api/v2/organizations/$org/environments/$env/deployments"
dep=$(curl -sS "${H[@]}" "$base" | jq -r --arg n "$app" '.items[] | select(.name==$n) | .id' | head -1)
[ -n "$dep" ] || { echo "ch2-public-url: デプロイ $app が見つかりません" >&2; exit 2; }
cur=$(curl -sS "${H[@]}" "$base/$dep")
url=$(printf '%s' "$cur" | jq -r '.target.deploymentSettings.http.inbound.publicUrl // empty')
if [ -z "$url" ]; then
  # 既存の target を保ったまま generateDefaultPublicUrl を足す (modify と違い properties は触らない)
  body=$(printf '%s' "$cur" | jq '{target: (.target | {targetId, provider, replicas, deploymentSettings: ((.deploymentSettings // {}) + {generateDefaultPublicUrl: true, http: {inbound: ((.deploymentSettings.http.inbound // {}) + {pathRewrite: "/"})}})})}')
  curl -sS -X PATCH "${H[@]}" "$base/$dep" -d "$body" >/dev/null
  for i in $(seq 1 20); do
    url=$(curl -sS "${H[@]}" "$base/$dep" | jq -r '.target.deploymentSettings.http.inbound.publicUrl // empty'); [ -n "$url" ] && break; sleep 5
  done
fi
[ -n "$url" ] || { echo "ch2-public-url: 公開 URL がまだ付きません (Runtime Manager で確認)" >&2; exit 1; }
echo "https://$url"
