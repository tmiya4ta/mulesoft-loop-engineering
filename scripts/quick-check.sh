#!/usr/bin/env bash
# 段 1 の検証器: 編集されたファイルに応じて数秒で終わる検査だけを行う。
# 失敗は stderr と exit 2 で Claude Code に返す (hook の規約)。
set -u
input=$(cat)
file=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

fail() { echo "quick-check: $*" >&2; exit 2; }

case "$file" in
  *.dwl)
    if command -v dw >/dev/null 2>&1; then
      dw -f "$file" >/dev/null 2>/tmp/qc.err || fail "DataWeave の構文エラー: $(head -5 /tmp/qc.err)"
    fi
    ;;
  */src/main/mule/*.xml)
    if command -v xmllint >/dev/null 2>&1; then
      xmllint --noout "$file" 2>/tmp/qc.err || fail "Mule XML が壊れています: $(head -3 /tmp/qc.err)"
    fi
    # 層の越境: System 層以外から DB / SAP コネクタを直接使っていないか
    layer=$(sed -n 's/^layer:[[:space:]]*//p' CLAUDE.md 2>/dev/null | head -1)
    if [ -n "$layer" ] && [ "$layer" != "system" ]; then
      grep -Eq '<db:|<sap:|<salesforce:' "$file" && fail "$layer 層から System コネクタを直接使っています。System API 経由にしてください。"
    fi
    ;;
  */tasks/T-*.md)
    grep -q '^done_when:[[:space:]]*[^[:space:]]' "$file" || fail "ゴール $file に done_when がありません。done_when の無いゴールは作れません。"
    ;;
  *.raml)
    if command -v api-console >/dev/null 2>&1; then :; fi
    ;;
esac
exit 0
