#!/usr/bin/env bash
# hook を起動するだけの薄い包み。**python の名前が環境で違う**ので、ここで吸収する。
#
# なぜ必要か。v0.6.44 で hook 7 本を Python にしたとき、hooks.json から `python3 <hook>.py` と
# 直接呼ぶ形にした。ところが Windows (Git Bash) では python.org 版を入れると `python` しか無く、
# `python3` は解決しません。**そのとき hook は「コマンドが無い」で終わり、deny する仕掛けが
# 全部黙って消えます** — このリポジトリで一番避けたい壊れ方 (効いていないことに気付けない)。
# だから名前を 3 つ試します: python3 → python → py -3。
#
# 使い方 (hooks.json から): bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-hook.sh <hook>.py
# 標準入力 (hook の JSON) と終了コードはそのまま素通しします。
#
# **python がどれも無いときは exit 0 で通し、標準エラーに 1 行出します。** 止めないのは、
# 道具が無いことを理由に作業全体を塞ぐのは筋が違うためです (preflight.sh が波の前に名指しします)。
set -u
hook=${1:?使い方: run-hook.sh <hook>.py}
shift || true
# `dirname` も使わない (bash の展開だけで出す)。PATH が痩せた環境でも壊れないようにするため。
dir=${0%/*}; [ "$dir" = "$0" ] && dir=.
target="$dir/$hook"
[ -f "$target" ] || { echo "run-hook: $target が無い" >&2; exit 0; }

for py in python3 python; do
  if command -v "$py" >/dev/null 2>&1; then
    exec "$py" "$target" "$@"
  fi
done
if command -v py >/dev/null 2>&1; then      # Windows の py ランチャー
  exec py -3 "$target" "$@"
fi
echo "run-hook: python が見つからないので $hook を実行できません (hook が効きません)。python3 を入れてください。" >&2
exit 0
