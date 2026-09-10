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
[ "$rc" -eq 0 ] && echo "fixtures-check: 全件期待どおり" || echo "fixtures-check: 期待と違う結果がある" >&2
exit "$rc"
