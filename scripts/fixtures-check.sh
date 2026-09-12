#!/usr/bin/env bash
# knowledge/fixtures/ の入力に対して、検査が期待どおり弾く / 素通りすることを確かめる。
# **弾けない検査は昇格していない** (台帳 test-toothless 6 件のうち 5 件が「一度も走っていなかった」)。
# 使い方: bash scripts/fixtures-check.sh   → exit 0 = 全件期待どおり
set -u
cd "$(dirname "$0")/.." || exit 1
rc=0
for f in knowledge/fixtures/bad-*.xml; do
  bash scripts/mule-xml-shape.sh "$f" >/dev/null 2>&1
  if [ $? -eq 2 ]; then echo "  ok   弾いた   $f"
  else echo "  NG   素通り   $f (この検査に牙が無い)" >&2; rc=1; fi
done
for f in knowledge/fixtures/ok-*.xml; do
  if bash scripts/mule-xml-shape.sh "$f" >/dev/null 2>&1; then echo "  ok   素通り   $f"
  else echo "  NG   誤検知   $f (正しい形を弾いている)" >&2; rc=1; fi
done
# secret-guard は入力が hook の JSON + 環境変数なので、入力をここに埋め込んで試す。
# **値そのものが deny の理由に出ないこと**も確かめる (出たら弾く意味が無い)。
SEC='TESTSECRET-abcdef123456'
sg() { printf '%s' "$1" | env ANYPOINT_CLIENT_SECRET="$SEC" python3 scripts/secret-guard.py 2>/dev/null; }

out=$(sg "{\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"memo secret=$SEC\"}}")
if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then echo "  ok   弾いた   secret-guard: 値をそのまま書く"
else echo "  NG   素通り   secret-guard: 値をそのまま書いても弾かない" >&2; rc=1; fi
if printf '%s' "$out" | grep -q "$SEC"; then echo "  NG   値漏れ   secret-guard: deny の理由に値が出ている" >&2; rc=1
else echo "  ok   値なし   secret-guard: deny の理由に値が出ていない"; fi

out=$(sg "{\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"memo: 接続に成功した\"}}")
if [ -z "$out" ]; then echo "  ok   素通り   secret-guard: 値を含まない書き込み"
else echo "  NG   誤検知   secret-guard: 値を含まないのに弾いた" >&2; rc=1; fi

out=$(sg "{\"tool_input\":{\"file_path\":\"/tmp/pom.xml\",\"content\":\"<x>\${env.ANYPOINT_CLIENT_SECRET}</x>\"}}")
if [ -z "$out" ]; then echo "  ok   素通り   secret-guard: \${env.X} の参照は弾かない"
else echo "  NG   誤検知   secret-guard: 参照の形を弾いた" >&2; rc=1; fi

[ "$rc" -eq 0 ] && echo "fixtures-check: 全件期待どおり" || echo "fixtures-check: 期待と違う結果がある" >&2
exit "$rc"
