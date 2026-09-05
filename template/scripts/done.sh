#!/usr/bin/env bash
# tasks/T-NNN.md の done_when を実行し、終了コードをそのまま返す。
# 進捗エージェントが実行エージェントの自己申告を信じずに使う。
set -u
f="${1:?usage: done.sh tasks/T-NNN.md}"
cmd=$(sed -n 's/^done_when:[[:space:]]*//p' "$f" | head -1)
[ -z "$cmd" ] && { echo "done_when がありません: $f" >&2; exit 3; }
echo "+ $cmd"
bash -c "$cmd"
