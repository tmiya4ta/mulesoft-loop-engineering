#!/usr/bin/env bash
# API Manager のポリシーを、探す / 設定項目を見る / 一覧する / 付ける / 外す。
#
# なぜ必要か。ポリシーは「どの資産を、どの設定で付けるか」が分からないと 1 行も書けないのに、
# 資産の座標 (groupId / assetId / version) も設定キーも画面にしか無いと思われていた。実際は
# Exchange とポリシーのスキーマから取れる。**しかも設定は検証されない** — 存在しないキーを渡しても
# 201 が返り、「適用済み」として一覧に並ぶ (実測)。推測すると、間違いに気付けないまま進む。
# 設定キーは `config` で取ってから書き、効いたかは `policy-check.sh` で実測する。
#
# 使い方:
#   bash scripts/policy.sh find <語>                     付けられるポリシーを探す (assetId と version)
#   bash scripts/policy.sh config <assetId> [<version>]  そのポリシーの設定キー (推測しないために必ず見る)
#   bash scripts/policy.sh list <インスタンス>            そのインスタンスに今付いているもの (policyId と順)
#   bash scripts/policy.sh apply <インスタンス> <assetId> [<version>] [--config '<JSON>'|@<file>]
#   bash scripts/policy.sh remove <インスタンス> <policyId>
# <インスタンス> は API インスタンス ID / instanceLabel / assetId (gateway-public-url.sh と同じ)。
#
# **apply と remove は `context/deployment/authorizations.yaml` の `policy.sandbox: allowed` が要る。**
# 書き換えるのは人。エージェントは読むだけ。環境名が Production 系なら、許可があっても止まる。
# 資格情報は anypoint-api.sh と同じ環境変数 (ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)。
#
# 実測 (2026-09-12、flexGateway のインスタンス):
#   apply  → 201。作られたポリシーの JSON が返る (`id` が policyId)。**実装資産は自動で選ばれる**
#            (client-id-enforcement 1.3.3 を付けると implementationAsset は client-id-enforcement-flex 1.2.0)
#   remove → 204 (本文なし)。一覧から消える
#   付けただけでは守れない。**必ず `policy-check.sh` で実測する** (認証なし 401 / あり 2xx)。
#
# exit 0 = できた / 1 = API が失敗した、見つからない / 2 = 前提が無い (許可、資格情報、引数)
set -u
here=$(cd "$(dirname "$0")" && pwd)
err=$(mktemp); trap 'rm -f "$err"' EXIT
api() { bash "$here/anypoint-api.sh" "$@" 2>"$err"; }
fail() { cat "$err" >&2; exit "${1:-1}"; }   # anypoint-api.sh の終了コードをそのまま返す (2 = 前提が無い)
EXCHANGE_POLICY_GROUP=68ef9520-24e9-4cf2-b2f5-620025690913   # MuleSoft の公式ポリシー資産の groupId

usage() { sed -n '/^# 使い方:/,/^# \*\*apply/p' "$0" | sed 's/^# //; s/^#//'; exit 2; }
verb=${1:-}; shift || true
[ -n "$verb" ] || usage

# --- 共通: インスタンスを 1 件に決める ------------------------------------------------
am='/apimanager/api/v1/organizations/{org}/environments/{env}/apis'
resolve() {
  case "$1" in
    ''|*[!0-9]*)
      list=$(api "$am?limit=100") || fail $?
      ids=$(printf '%s' "$list" | jq -r --arg a "$1" \
        '.assets[]? | .assetId as $asset | .apis[]? | select($asset == $a or .instanceLabel == $a) | .id')
      n=$(printf '%s\n' "$ids" | grep -c .)
      [ "$n" -ge 1 ] || { echo "policy: '$1' という instanceLabel / assetId のインスタンスがこの環境に無い" >&2; exit 2; }
      [ "$n" -eq 1 ] || { echo "policy: '$1' に当たるインスタンスが $n 件。ID で指定する:" >&2
        printf '%s' "$list" | jq -r --arg a "$1" '.assets[]? | .assetId as $asset | .apis[]?
          | select($asset == $a or .instanceLabel == $a) | "  \(.id)  \(.instanceLabel // "-")  \($asset)"' >&2
        exit 2; }
      printf '%s' "$ids" ;;
    *) printf '%s' "$1" ;;
  esac
}

# --- 共通: Exchange からポリシー資産を引く --------------------------------------------
assets() { api "/exchange/api/v2/assets?types=policy&limit=${2:-50}&search=$1"; }

case "$verb" in
find)
  q=${1:?使い方: policy.sh find <語>   例: rate / jwt / client-id}
  out=$(assets "$q") || fail $?
  printf '%s' "$out" | jq -r 'sort_by(.assetId)[] | "\(.assetId)\t\(.version)\t\(.name // "")"' |
    awk -F'\t' '{printf "%-46s %-12s %s\n", $1, $2, $3}'
  n=$(printf '%s' "$out" | jq 'length')
  [ "${n:-0}" -gt 0 ] || { echo "policy: '$q' に当たるポリシーが無い (語を短く、英語で)" >&2; exit 1; }
  echo
  echo "設定キーを見る: bash scripts/policy.sh config <assetId>"
  ;;

config)
  a=${1:?使い方: policy.sh config <assetId> [<version>]}; v=${2:-}
  if [ -z "$v" ]; then
    v=$(assets "$a" 100 | jq -r --arg a "$a" '[.[] | select(.assetId == $a)][0].version // empty') || fail $?
    [ -n "$v" ] || { echo "policy: ポリシー資産 '$a' が見つからない (bash scripts/policy.sh find <語> で探す)" >&2; exit 1; }
  fi
  detail=$(api "/exchange/api/v2/assets/$EXCHANGE_POLICY_GROUP/$a/$v") || fail $?
  url=$(printf '%s' "$detail" | jq -r '.files[]? | select(.classifier == "schema" and .packaging == "json") | .externalLink // empty' | head -1)
  [ -n "$url" ] || { echo "policy: $a $v に設定スキーマ (schema.json) が無い" >&2; exit 1; }
  echo "$a $v  (groupId $EXCHANGE_POLICY_GROUP)"
  # スキーマは if / then / else で「この値のときだけ要る項目」を表すことがあるので、その枝も出す
  curl -sS -m 60 "$url" -o "$err.sc"
  jq -r '
    def rows($src; $req; $tag):
      ($src // {}) | to_entries[] | . as $e
      | "\($tag)\($e.key)\t\($e.value.type // "?")\t\(if (($req // []) | index($e.key)) then "必須" else "任意" end)\t\(($e.value.description // $e.value.title // "") | split("\n")[0])";
    rows(.properties; .required; ""),
    rows(.then.properties; .then.required; "(条件つき) "),
    rows(.else.properties; .else.required; "(条件つき) ")' "$err.sc" |
    awk -F'\t' '{printf "  %-46s %-8s %-4s %s\n", $1, $2, $3, substr($4,1,64)}'
  jq -r '[.. | objects | select(has("oneOf")) | .oneOf[]? | select(has("const")) | "\(.const)"] | unique
         | if length > 0 then "  選べる値: " + join(" / ") else empty end' "$err.sc"
  rm -f "$err.sc"
  echo
  echo "付ける: bash scripts/policy.sh apply <インスタンス> $a $v --config '{\"<キー>\": <値>}'"
  ;;

list)
  id=$(resolve "${1:?使い方: policy.sh list <インスタンス>}")
  api "$am/$id/policies" > "$err.out" || fail $?
  jq -r '.policies[]? | "\(.policyId)\t\(.template.assetId)\t\(.template.assetVersion)\torder \(.order)\t\(.configuration | tostring | .[0:60])"' "$err.out" |
    awk -F'\t' '{printf "%-10s %-34s %-10s %-9s %s\n", $1, $2, $3, $4, $5}'
  n=$(jq '.policies | length' "$err.out"); rm -f "$err.out"
  echo; echo "$n 件。効いているかは表示ではなく bash scripts/policy-check.sh <URL> client-id <path> で決める"
  ;;

apply|remove)
  # 許可の確認 (deploy-guard.sh と同じ形。ファイルを書き換えるのは人)
  root=$PWD; while [ -n "$root" ]; do
    [ -f "$root/context/deployment/authorizations.yaml" ] && break
    [ -e "$root/.git" ] && { root=""; break; }
    parent=$(dirname "$root"); [ "$parent" = "$root" ] && { root=""; break; }; root=$parent
  done
  auth="${root:+$root/context/deployment/authorizations.yaml}"
  ok=$(sed -n '/^policy:/,/^[^ ]/p' "${auth:-/dev/null}" 2>/dev/null | sed -n 's/^[[:space:]]*sandbox:[[:space:]]*\([a-z-]*\).*/\1/p' | head -1)
  [ "$ok" = allowed ] || {
    echo "policy: authorizations.yaml の policy.sandbox が '${ok:-無し}' なので $verb はしない。" >&2
    echo "  許可を書くのは人 (${auth:-context/deployment/authorizations.yaml})。**自分で書き換えない。**" >&2
    echo "  理由をそのまま人に伝えて止まる。" >&2
    exit 2; }
  envname=${ANYPOINT_ENV:-$(sed -n 's/^environment:[[:space:]]*\([^#]*\).*/\1/p' "${root:-.}/context/deployment/sandbox.yaml" 2>/dev/null | head -1)}
  case "$(printf '%s' "$envname" | tr '[:upper:]' '[:lower:]')" in
    *prod*|*本番*) echo "policy: 環境 '$envname' は本番系。許可があっても止まる (本番は人が手で行う)" >&2; exit 2 ;;
  esac

  id=$(resolve "${1:?使い方: policy.sh $verb <インスタンス> ...}"); shift
  inst=$(api "$am/$id") || fail $?
  org=$(printf '%s' "$inst" | jq -r .organizationId); envid=$(printf '%s' "$inst" | jq -r .environmentId)
  host=${ANYPOINT_HOST:-https://anypoint.mulesoft.com}
  tok=$(printf '{"grant_type":"client_credentials","client_id":"%s","client_secret":"%s"}' \
          "${ANYPOINT_CLIENT_ID:?環境変数が要る}" "${ANYPOINT_CLIENT_SECRET:?環境変数が要る}" |
        curl -sS -m 30 -X POST "$host/accounts/api/v2/oauth2/token" -H 'content-type: application/json' -d @- |
        jq -r '.access_token // empty')
  [ -n "$tok" ] || { echo "policy: トークンが取れない" >&2; exit 2; }
  B="$host/apimanager/api/v1/organizations/$org/environments/$envid/apis/$id/policies"

  if [ "$verb" = remove ]; then
    pid=${1:?使い方: policy.sh remove <インスタンス> <policyId>   (policyId は list で見る)}
    code=$(curl -sS -m 60 -X DELETE -H "Authorization: Bearer $tok" -o "$err.out" -w '%{http_code}' "$B/$pid")
    case "$code" in 204|200) echo "policy: policyId $pid を外した (HTTP $code)" ;;
      *) echo "policy: 外せない (HTTP $code)" >&2; head -c 800 "$err.out" >&2; echo >&2; rm -f "$err.out"; exit 1 ;; esac
    rm -f "$err.out"
    echo "  守りが変わったので bash scripts/policy-check.sh <URL> ... を回し直す"
    exit 0
  fi

  a=${1:?使い方: policy.sh apply <インスタンス> <assetId> [<version>] [--config '<JSON>'|@<file>]}; shift
  v=""; cfg="{}"
  case "${1:-}" in --config) ;; "") ;; *) v=$1; shift ;; esac
  if [ "${1:-}" = --config ]; then
    c=${2:?--config の後に JSON か @<file>}
    case "$c" in @*) cfg=$(cat "${c#@}") ;; *) cfg=$c ;; esac
  fi
  printf '%s' "$cfg" | jq -e . >/dev/null 2>&1 || { echo "policy: --config が JSON ではない" >&2; exit 2; }
  if [ -z "$v" ]; then
    v=$(assets "$a" 100 | jq -r --arg a "$a" '[.[] | select(.assetId == $a)][0].version // empty') || fail $?
    [ -n "$v" ] || { echo "policy: ポリシー資産 '$a' が見つからない (bash scripts/policy.sh find <語>)" >&2; exit 1; }
    echo "policy: 版を省いたので Exchange の最新 $v を使う" >&2
  fi
  body=$(jq -n --arg g "$EXCHANGE_POLICY_GROUP" --arg a "$a" --arg v "$v" --argjson c "$cfg" \
    '{groupId: $g, assetId: $a, assetVersion: $v, configurationData: $c}')
  code=$(printf '%s' "$body" | curl -sS -m 60 -X POST -H "Authorization: Bearer $tok" \
           -H 'content-type: application/json' -d @- -o "$err.out" -w '%{http_code}' "$B")
  case "$code" in
    2*) pid=$(jq -r '.id // .policyId // "?"' "$err.out")
        impl=$(jq -r '.implementationAsset | "\(.assetId) \(.version) (\(.technology))"' "$err.out" 2>/dev/null)
        echo "policy: $a $v を付けた。policyId $pid / 実装 $impl (HTTP $code)"
        rm -f "$err.out"
        echo "  **付けただけでは守れているとは限らない。** bash scripts/policy-check.sh <URL> client-id <path> で実測する"
        echo "  外す: bash scripts/policy.sh remove $id $pid" ;;
    *) echo "policy: 付けられない (HTTP $code)" >&2; head -c 1000 "$err.out" >&2; echo >&2
       echo "  設定キーが違うことが多い: bash scripts/policy.sh config $a $v で確かめる" >&2
       echo "  ゲートウェイが対応していないポリシーもある (technology が合うかはエラー本文に出る)" >&2
       rm -f "$err.out"; exit 1 ;;
  esac
  ;;
*) usage ;;
esac
