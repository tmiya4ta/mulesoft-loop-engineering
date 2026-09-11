#!/usr/bin/env bash
# /mule-deploy の最初に 1 回だけ実行し、人に聞く必要があることを機械的にまとめて洗い出す。
# 無ければここで洗い出さず、pom を触ってからデプロイ直前や smoke-check で 1 件ずつ気づくことになり、
# ループが何度も止まる (inventory3-api T-006 で実測: Connected App の client_credentials、
# DB のパスワード、Private Space の指定が別々のタイミングで発覚し、都度止まった)。
# 使い方: bash scripts/deploy-precheck.sh
#   exit 0: 追加で聞くことは無い。そのまま進めてよい。
#   exit 1: 下に列挙した項目を **1 回のやり取りでまとめて** 人に確認してから進める。
set -u
need_ask=0

echo "== /mule-deploy 前の確認事項 (見つかったものを 1 回でまとめて聞く) =="

for v in ANYPOINT_CLIENT_ID ANYPOINT_CLIENT_SECRET; do
  if [ -z "${!v:-}" ]; then
    echo "- 環境変数 $v が未設定 (Connected App の client_credentials)。エクスポートしてもらう"
    need_ask=1
  fi
done

if [ -f context/deployment/sandbox.yaml ]; then
  target_line=$(grep -m1 '^target:' context/deployment/sandbox.yaml || true)
  kind_line=$(grep -m1 '^kind:' context/deployment/sandbox.yaml || true)
  echo "- デプロイ先: ${kind_line:-kind 不明} / ${target_line:-target 不明}"
  echo "  (shared space でよいか、Private Space を使うかを含めて確認する。違えば sandbox.yaml を直してもらう)"
fi

placeholders=""
if compgen -G "src/main/resources/config/*.yaml" > /dev/null 2>&1; then
  placeholders=$(grep -rho 'SET_[A-Z0-9_]*' src/main/resources/config/*.yaml 2>/dev/null | sort -u)
fi
if [ -n "$placeholders" ]; then
  echo "- 配備先で実値が要るプロパティ (config/*.yaml の SET_ プレースホルダ):"
  echo "$placeholders" | sed 's/^/    /'
  echo "  (名前に password / secret / credential を含むものは Runtime Manager の secure property。"
  echo "   それ以外は context/deployment/sandbox.yaml の properties に書いてよい)"
  need_ask=1
fi

if [ "$need_ask" = 1 ]; then
  echo
  echo "→ 上を 1 回の AskUserQuestion / メッセージにまとめて聞いてから、手順 2 (pom へのデプロイ設定投入) に進む。"
  echo "  1 件ずつ聞き直さない。"
  exit 1
fi
echo "- 追加の確認事項なし"
exit 0
