#!/usr/bin/env bash
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
# 使い方: bash scripts/gateway-public-url.sh <API インスタンス ID | instanceLabel | assetId>
#   標準出力: 外から叩く base URL。**末尾の / は付けない。後ろにリソース (/inventory など) を付けて使う**
#             (base だけを叩くと 404 になるのは正常)。policy-check.sh の 1 つ目にそのまま渡せる
#   標準エラー: 内側の URL、upstream、ゲートウェイを迂回できる恐れ
# 環境変数と組織・環境の解決は anypoint-api.sh と同じ (ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)。
#
# exit 0 = 出した / 1 = 外からの URL が無い (egress の港に置いた、self-managed、公開 URL 未設定)
#      2 = 前提が無い (資格情報、未配備、flexGateway でない、候補が複数)
set -u
arg=${1:?使い方: gateway-public-url.sh <API インスタンス ID | instanceLabel | assetId>}
here=$(cd "$(dirname "$0")" && pwd)
err=$(mktemp); trap 'rm -f "$err"' EXIT
api() { bash "$here/anypoint-api.sh" "$@" 2>"$err"; }
fail() { cat "$err" >&2; exit 2; }
am='/apimanager/api/v1/organizations/{org}/environments/{env}/apis'

case "$arg" in
  *[!0-9]*)
    list=$(api "$am?limit=100") || fail
    ids=$(printf '%s' "$list" | jq -r --arg a "$arg" \
      '.assets[]? | .assetId as $asset | .apis[]? | select($asset == $a or .instanceLabel == $a) | .id')
    n=$(printf '%s\n' "$ids" | grep -c .)
    [ "$n" -ge 1 ] || { echo "gateway-public-url: '$arg' という instanceLabel / assetId のインスタンスがこの環境に無い" >&2; exit 2; }
    if [ "$n" -gt 1 ]; then
      echo "gateway-public-url: '$arg' に当たるインスタンスが $n 件。ID で指定する:" >&2
      printf '%s' "$list" | jq -r --arg a "$arg" '.assets[]? | .assetId as $asset | .apis[]?
        | select($asset == $a or .instanceLabel == $a) | "  \(.id)  \(.instanceLabel // "-")  \($asset)"' >&2
      exit 2
    fi
    id=$ids ;;
  *) id=$arg ;;
esac

inst=$(api "$am/$id") || fail
tech=$(printf '%s' "$inst" | jq -r '.technology // empty')
gw=$(printf '%s' "$inst" | jq -r '.deployment.targetId // empty')
gwname=$(printf '%s' "$inst" | jq -r '.deployment.targetName // empty')
proxy=$(printf '%s' "$inst" | jq -r '.endpoint.proxyUri // empty')
up=$(printf '%s' "$inst" | jq -r '.endpoint.uri // empty')
[ "$tech" = flexGateway ] || { echo "gateway-public-url: インスタンス $id の technology は '$tech' (flexGateway ではない)。対象外" >&2; exit 2; }
[ -n "$gw" ] || { echo "gateway-public-url: インスタンス $id はまだどのゲートウェイにも配備されていない (deployment が空)" >&2; exit 2; }
[ -n "$proxy" ] || { echo "gateway-public-url: インスタンス $id に endpoint.proxyUri が無い" >&2; exit 2; }

if ! g=$(api "/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways/$gw"); then
  if grep -q 'HTTP 404' "$err"; then
    echo "gateway-public-url: ゲートウェイ $gwname は Gateway Manager に無い = self-managed。" >&2
    echo "  外からの URL は、それを動かしている側 (人) が決める。ゲートウェイ内の待ち受けは $proxy" >&2
    exit 1
  fi
  fail
fi

port=$(printf '%s' "$proxy" | sed -n 's#^[a-z]*://[^/:]*:\([0-9][0-9]*\).*#\1#p')
path=$(printf '%s' "$proxy" | sed -n 's#^[a-z]*://[^/]*\(/.*\)$#\1#p'); path=${path%/}
in=$(printf '%s' "$g" | jq -r '.portConfiguration.ingress.port // empty')
eg=$(printf '%s' "$g" | jq -r '.portConfiguration.egress.port // empty')
if [ -n "$in" ] && [ -n "$port" ] && [ "$port" != "$in" ]; then
  if [ "$port" = "$eg" ]; then
    echo "gateway-public-url: この API は egress の港 ($eg) に置かれている。外からの URL は無い。" >&2
    echo "  Private Space の内側から $(printf '%s' "$g" | jq -r '.clusterUrl // empty' | sed 's#/$##')$path でだけ届く。" >&2
    echo "  外から叩きたいなら proxyUri を港 $in で作り直す。" >&2
  else
    echo "gateway-public-url: proxyUri の港 $port は、ゲートウェイの ingress ($in) でも egress ($eg) でもない" >&2
  fi
  exit 1
fi

# endpoints[] (access と pathRewrite 付き) を優先。無ければ publicUrl / internalUrl (カンマ区切り) を使う
urls() {  # <external|internal> → "URL<TAB>pathRewrite" を 1 行ずつ
  printf '%s' "$g" | jq -r --arg a "$1" '
    .configuration.ingress as $i
    | [$i.endpoints[]? | select(.access == $a) | "\(.url)\t\(.pathRewrite // "/")"] as $e
    | if ($e | length) > 0 then $e[]
      else (if $a == "external" then $i.publicUrl else $i.internalUrl end) // ""
           | split(",")[] | select(length > 0) | "\(.)\t/" end'
}
build() {  # <url> <pathRewrite> → 外からの URL
  u=${1%/}; pr=${2%/}
  case "$path" in "$pr"|"$pr"/*) printf '%s%s\n' "$u" "${path#"$pr"}" ;; *) return 1 ;; esac
}
out=""
while IFS="$(printf '\t')" read -r u pr; do
  [ -n "$u" ] || continue
  r=$(build "$u" "$pr") || { echo "  (公開 URL $u は pathRewrite $pr なので $path には届かない)" >&2; continue; }
  if [ -z "$out" ]; then out=$r; else echo "  別の公開 URL: $r" >&2; fi
done <<EOF
$(urls external)
EOF
[ -n "$out" ] || { echo "gateway-public-url: ゲートウェイ $gwname に公開 URL が設定されていない (configuration.ingress)" >&2; exit 1; }

while IFS="$(printf '\t')" read -r u pr; do
  [ -n "$u" ] && r=$(build "$u" "$pr") && echo "  内側の URL (同じ Private Space から): $r" >&2
done <<EOF
$(urls internal)
EOF
echo "  ゲートウェイ $gwname / 待ち受け $proxy / upstream $up" >&2
# upstream が外から直接届くなら、ゲートウェイを迂回してポリシーを素通りできる
case "$up" in
  http*://*internal*|"") ;;
  *) c=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$up" 2>/dev/null) || c=000
     [ "$c" = 000 ] || {
       echo "  **注意**: upstream $up に外から直接届く (HTTP $c)。ゲートウェイを迂回すればポリシーは効かない。" >&2
       echo "  Proxy 型では upstream をアプリの内部 URL にし、アプリの公開 URL を消す (knowledge/gotchas/api-manager.md)。" >&2
     } ;;
esac
printf '%s\n' "$out"
