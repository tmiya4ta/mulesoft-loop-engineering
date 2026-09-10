#!/usr/bin/env bash
# 次に使う K ファイル (調べた事実の記録) のパスを出す。**番号を手で選ばせない。**
#
# なぜ必要か。並列の実行エージェントが同じ `K-NNN.md` を独立に選び、取り込みで衝突した
# 実例がある (failures.jsonl: `knowledge-file-number-collision`)。名前にゴール id を入れれば
# **別のゴールとは構造的に衝突しない** (ゴール id が違う)。同じゴールの中の書き手は 1 つだけ。
#
# 実際に 4 通りに散っていた: `K-001.md` / `K-009-1.md` / `K-T-001-1.md` / `K-T-003-1.md`。
# しかも `K-001.md` は 2 つのプロジェクトの両方にあった。手で選ぶ限りこれは揃わない。
#
# 使い方:
#   bash scripts/k-new.sh T-003   → knowledge/K-T-003-1.md   (実行エージェント。ゴール id をそのまま)
#   bash scripts/k-new.sh learn   → knowledge/K-learn-1.md    (/mule-learn の昇格の記録)
#
# **ファイルは作りません。パスだけ出します。** 空の K ファイルが diff に現れると、
# `/mule-run` の「K ファイルが diff に含まれているか」の確認が「学びの記録あり」と
# 誤判定します (牙の無い検査になる)。中身を書くのは呼んだ側です。
set -u

id=${1:-}
[ -n "$id" ] || { echo "k-new: ゴール id が必要 (例: T-003、または /mule-learn なら learn)" >&2; exit 2; }
case "$id" in
  *[/\\]*|.|..) echo "k-new: ゴール id にパス区切りは使えない: $id" >&2; exit 2 ;;
esac

n=1
while [ -e "knowledge/K-$id-$n.md" ]; do n=$((n+1)); done
printf 'knowledge/K-%s-%s.md\n' "$id" "$n"
