#!/usr/bin/env bash
# フローのカバレッジを構造的に確認する。EE ライセンスが無くても必ず動く。
# src/main/mule/*.xml の全 flow / sub-flow が、src/test/munit/*.xml のどれかから
# flow-ref されているかを見る。未カバーが 1 つでもあれば exit 1。
set -u
main="${1:-src/main/mule}"; test="${2:-src/test/munit}"
[ -d "$main" ] || { echo "no $main" >&2; exit 0; }
flows=$(grep -rhoE '<(sub-)?flow +name="[^"]+"' "$main" 2>/dev/null | sed 's/.*name="//;s/"//' | sort -u)
[ -z "$flows" ] && { echo "flow がありません"; exit 0; }
refs=$(grep -rhoE '(flow-ref +name|munit:execution[^>]*>.*name)="[^"]+"' "$test" 2>/dev/null | sed 's/.*name="//;s/"//' | sort -u)
miss=""; n=0; c=0
while IFS= read -r f; do
  n=$((n+1))
  if printf '%s\n' "$refs" | grep -qxF "$f"; then c=$((c+1)); else miss="$miss $f"; fi
done <<< "$flows"
pct=$(( n>0 ? c*100/n : 100 ))
echo "flow coverage: $c/$n (${pct}%)"
if [ -n "$miss" ]; then
  echo "未カバーの flow:$miss" >&2
  echo "→ 各 flow を flow-ref する munit:test を追加してください" >&2
  exit 1
fi
