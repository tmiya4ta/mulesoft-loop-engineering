#!/usr/bin/env bash
# PreToolUse(Bash) hook。**プラグイン本体のリポジトリで `gh pr create` を打つ前に、
# 索引と hook の検査を通っていることを確かめる。**
#
# なぜ必要か。`knowledge-index-check.sh` と `fixtures-check.sh` は `/mule-learn` の手順が呼ぶ
# 検査で、**呼び忘れても誰も気付きません**。しかも忘れたときに起きることが厄介です:
#   - 索引がずれる → 読む側は「合う行が無い」と判断してそのファイルを開かず、書いた項目が読まれない
#     (v0.6.15 は索引の行数を 19 個ずらし、PR #2 は件数を 11 のまま残した)
#   - hook の牙が無い → 弾いているつもりで素通りしている (台帳 test-toothless の 5/6 がこれ)
# どちらも **PR がマージされた後に効いてくる**ので、PR を開く前が最後の関所です。
#
# 対象は `gh pr create` を含む Bash コマンドで、**このリポジトリ (mule-loop 本体) にいるときだけ**。
# 利用者のプロジェクトには knowledge/ の索引も fixtures も無いので、そこでは何もしません。
set -u
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("command",""))' 2>/dev/null) || exit 0
printf '%s' "$cmd" | grep -q 'gh[[:space:]]\+pr[[:space:]]\+create' || exit 0

# mule-loop 本体かどうかは「検査スクリプトが両方あるか」で決める (パスを推測しない)
[ -f scripts/knowledge-index-check.sh ] && [ -f scripts/fixtures-check.sh ] || exit 0

fails=""
for s in knowledge-index-check fixtures-check; do
  out=$(bash "scripts/$s.sh" 2>&1) || fails="$fails\n--- $s.sh\n$out"
done
[ -z "$fails" ] && exit 0

python3 - "$fails" <<'PY'
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason":
        "PR を開く前の検査が通っていません。**直してから開いてください。**"
        + sys.argv[1].replace("\\n", "\n") +
        "\n索引がずれると、読む側は「合う行が無い」と判断してそのファイルを開かず、"
        "書いた項目が誰にも読まれません。hook の牙が無いと、弾いているつもりで素通りします。"
        "\nどちらも PR がマージされた後に効いてくるので、ここが最後の関所です。"
}}, ensure_ascii=False))
PY
