#!/usr/bin/env bash
# 波を配る前に、全ゴールが共有する土台を 1 回だけ確かめる。
# 目的は「N 体が同じ原因で各 3 回試して全滅する」のを防ぐこと。コスト 1 回で N×3 を止める。
#
# 見るのは、どのゴールにも共通する前提だけ:
#   依存の解決 (Exchange の 401、推測した GAV、手書き pom)、Java、アプリが固まること。
#
# **MUnit は流さない。** 実行ループの途中では失敗したゴールの red なテストが木に残っており、
# mvn test は設計どおり赤くなる。それで波を止めると、毎回 1 件目のゴール失敗で全部止まる。
# 使うコマンドは mule-init 手順 5b と同じもの (実績のある「このプロジェクトはビルドできるか」の検査)。
#
# exit 0 = 土台は健全。exit 2 = 落ちた (1 件も配らない)。
set -u

[ -f pom.xml ] || { echo "preflight: pom.xml が無い (/mule-init が済んでいない)" >&2; exit 2; }

cmd="mvn -q clean package -DskipTests"
out=$($cmd 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  {
    echo "preflight: \`$cmd\` が exit $rc で落ちた。土台が壊れているので この波は 1 件も配らない。"
    echo "--- 出力 (原文、末尾 40 行) ---"
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi
echo "preflight: ok ($cmd)"

# スキーマ索引を pom.xml より古ければ作り直す。~/.m2 は上の package で埋まっている。
# **ここの失敗で波を止めない。** 土台の判定はあくまで上の package の結果で、
# 索引はあると速くなる補助にすぎない (無ければエージェントは gotchas → スキルの順に戻るだけ)。
idx=reference/mule-schema/INDEX.md
if [ -f scripts/schema-index.sh ] && { [ ! -f "$idx" ] || [ pom.xml -nt "$idx" ]; }; then
  bash scripts/schema-index.sh || echo "preflight: schema-index は失敗した (波は止めない)" >&2
fi
