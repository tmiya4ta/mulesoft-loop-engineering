#!/usr/bin/env bash
# Anypoint Platform API を **GET だけ**叩く共通の入口。トークン・組織 ID・環境 ID を解決して応答を出す。
#
# なぜ必要か。Anypoint にある値 (公開 URL、ゲートウェイの ID、インスタンスの状態) を、API で取れるのに
# 「分からない」と止まって人に画面を見てもらっていた (inventory3-api T-007、2026-09-11)。
# 叩くたびにトークン取得の curl を書き直し、Connected App の Secret をコマンド行に直接書いてもいた
# (会話の記録に残る)。ここに寄せれば Secret は環境変数から読むだけで、どこにも出ない。
#
# どの API のどのパスに目当ての値があるかは `bash scripts/portal-search.sh '<項目名>'` で引く。
# そこで出た行をそのまま流せば動く。
#
# 使い方:
#   bash scripts/anypoint-api.sh '/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways'
#   bash scripts/anypoint-api.sh '/apimanager/api/v1/organizations/{org}/environments/{env}/apis/<id>' | jq .deployment
#   bash scripts/anypoint-api.sh '<パス>' --find publicUrl     # 応答の中で名前に publicUrl を含む項目だけ出す
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
set -u
p=${1:-}; shift || true
find=""
[ "${1:-}" = "--find" ] && find=${2:?--find の後に項目名}
case "$p" in
  /*) ;;
  *) echo "使い方: anypoint-api.sh '/<API のパス>' [--find <項目名>]   (ホスト名は付けない。例: /accounts/api/me)" >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "anypoint-api: jq が無い" >&2; exit 2; }
host=${ANYPOINT_HOST:-https://anypoint.mulesoft.com}
if [ -z "${ANYPOINT_CLIENT_ID:-}" ] || [ -z "${ANYPOINT_CLIENT_SECRET:-}" ]; then
  echo "anypoint-api: 環境変数 ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET が無い。" >&2
  echo "  Claude Code の Bash は毎回新しいシェルなので、人に「export してから claude を起動し直す」を頼む。" >&2
  echo "  **値を会話・コマンド行・台帳・ファイルに書かない。** 会話で渡されても export ...=<値> と打たずに頼む" >&2
  echo "  (ファイルに書くと /mule-run の git add -A でコミットに入ることがある)。" >&2
  exit 2
fi

# Secret を curl の引数に出さない (printf は bash の組み込みなので、プロセス一覧にも残らない)
tok=$(printf '{"grant_type":"client_credentials","client_id":"%s","client_secret":"%s"}' \
        "$ANYPOINT_CLIENT_ID" "$ANYPOINT_CLIENT_SECRET" |
      curl -sS -m 30 -X POST "$host/accounts/api/v2/oauth2/token" -H 'content-type: application/json' -d @- |
      jq -r '.access_token // empty' 2>/dev/null)
[ -n "$tok" ] || { echo "anypoint-api: トークンが取れない (Connected App の ID / Secret か、ANYPOINT_HOST の地域を確かめる)" >&2; exit 2; }
auth=(-H "Authorization: Bearer $tok")

p=$(printf '%s' "$p" | sed 's/{organizationId}/{org}/g; s/{orgId}/{org}/g; s/{environmentId}/{env}/g; s/{envId}/{env}/g')
org=${ANYPOINT_ORG:-$(sed -n 's/.*<groupId>\([0-9a-f-]\{36\}\)<\/groupId>.*/\1/p' pom.xml 2>/dev/null | head -1)}
case "$p" in *'{org}'*|*'{env}'*)
  [ -n "$org" ] || { echo "anypoint-api: 組織 ID が分からない (pom.xml の groupId が組織 ID でない)。ANYPOINT_ORG=<組織 ID> で渡す" >&2; exit 2; }
esac
case "$p" in *'{env}'*)
  en=${ANYPOINT_ENV:-$(sed -n 's/^environment:[[:space:]]*\([^#]*\).*/\1/p' context/deployment/sandbox.yaml 2>/dev/null | head -1)}
  en=$(printf '%s' "$en" | sed 's/[[:space:]]*$//; s/^"\(.*\)"$/\1/')
  [ -n "$en" ] || { echo "anypoint-api: 環境名が分からない。ANYPOINT_ENV=<環境名> で渡すか、sandbox.yaml の environment を人に埋めてもらう" >&2; exit 2; }
  if printf '%s' "$en" | grep -Eq '^[0-9a-f-]{36}$'; then env=$en; else
    env=$(curl -sS -m 30 "${auth[@]}" "$host/accounts/api/organizations/$org/environments" |
          jq -r --arg n "$en" '.data[]? | select(.name == $n) | .id' | head -1)
  fi
  [ -n "$env" ] || { echo "anypoint-api: 環境 '$en' が組織 $org に無い (名前は大文字小文字まで一致させる)" >&2; exit 2; }
  p=$(printf '%s' "$p" | sed "s/{env}/$env/g") ;;
esac
[ -n "$org" ] && p=$(printf '%s' "$p" | sed "s/{org}/$org/g")
case "$p" in *'{'*'}'*)
  echo "anypoint-api: パスに埋めていない変数がある: $(printf '%s' "$p" | grep -o '{[^}]*}' | tr '\n' ' ')" >&2
  echo "  その値は、同じ API の一覧の操作で取る (portal-search.sh の「の値」の行に書いてある)" >&2
  exit 2 ;;
esac

# 空の配列を "${a[@]}" で展開すると macOS の bash 3.2 は set -u で落ちるので ${a[@]+...} で包む
hdr=(); [ -n "$org" ] && hdr+=(-H "X-ANYPNT-ORG-ID: $org"); [ -n "${env:-}" ] && hdr+=(-H "X-ANYPNT-ENV-ID: $env")
out=$(mktemp); trap 'rm -f "$out"' EXIT
code=$(curl -sS -m 60 -o "$out" -w '%{http_code}' "${auth[@]}" ${hdr[@]+"${hdr[@]}"} "$host$p" 2>/dev/null) || code=000
case "$code" in
  2*) ;;
  *) echo "anypoint-api: GET $p → HTTP $code" >&2
     head -c 1500 "$out" >&2; echo >&2
     case "$code" in
       401|403) echo "  Connected App にこの API のスコープが無い。足すのは人 (組織管理者)。どのスコープかは portal-search.sh の仕様の description にある" >&2 ;;
       404) echo "  パスか ID が違う。ID は一覧の操作 (list...) で取り直す。組織・環境が違うこともある" >&2 ;;
       000) echo "  $host に届かない (ネットワーク、または ANYPOINT_HOST の地域)" >&2 ;;
     esac
     exit 1 ;;
esac
if [ -z "$find" ]; then cat "$out"; echo; exit 0; fi
hits=$(jq -r --arg w "$find" '
  paths(scalars) as $p
  | ($p | map(tostring) | join(".")) as $s
  | select($p | map(tostring) | map(ascii_downcase) | any(contains($w | ascii_downcase)))
  | "\($s) = \(getpath($p))"' "$out" 2>/dev/null)
[ -n "$hits" ] || { echo "anypoint-api: 応答に '$find' を名前に含む項目は無い (応答全体は --find を外して見る)" >&2; exit 1; }
printf '%s\n' "$hits"
