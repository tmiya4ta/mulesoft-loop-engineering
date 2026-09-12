#!/usr/bin/env bash
# 「そのテストに牙があるか」を機械が測る。**人が手で細工して目で見るのをやめる。**
#
# なぜ必要か。台帳の `test-toothless` 6 件のうち **5 件が「検査自体が一度も走っていなかった」**で、
# しかもその 3 件は**牙の確認そのものが当たっていなかった**もの:
#   - `mutation-test-wrong-failure-path`: 別の前処理が先に落ちて exit 1。狙った case は未実行
#   - `tamper-missed-due-to-line-number-drift`: 行番号決め打ちの sed が外れ、細工が 1 文字も当たらず
#     「緑だから牙が無い」と誤読しかけた
#   - `uncaught-exception-in-check-prelude`: 前処理の例外でスタックトレースだけ出て NG 行ゼロ、exit 1
# 共通の誤りは **exit が非ゼロになったことを牙の証拠にした**こと。ここでは 3 つ全部を機械が見ます:
#   (1) 細工が当たったか  (2) 細工前は緑だったか  (3) 狙った case が失敗として出力に現れたか
#
# MUnit の出力の形は推測ではなく実測 (finance-api name-test.xml、2026-09-10):
#   細工前: `= Tests run: 7 - Failed: 0 - Errors: 0 - Skipped: 0 ... =`
#   細工後: `munit.01 ERROR FAILURE - test: name-not-found - Time elapsed: 0.03 sec`
#           `= Tests run: 7 - Failed: 1 - Errors: 0 - Skipped: 0 ... =`
# だから `FAILURE - test: <case 名>` と `Failed: <1 以上>` の 2 つを条件にします。
# exit が非ゼロでもこの 2 つが揃わなければ **狙った検査は走っていない** ので牙は示せていません。
#
# 使い方:
#   bash scripts/teeth-check.sh --file src/test/munit/name-test.xml \
#        --old 'MunitTools::equalTo(vars.expected.status)' --new 'MunitTools::equalTo(999)' \
#        --case name-not-found
#   (--munit を省くと --file の basename を使う。実装側を壊すときは --munit で指定する)
#   --skip-baseline で細工前の 1 回目を省略できる (直前に緑を確認済みのときだけ)
#
# **対象ファイルは必ず元に戻します** (trap。異常終了でも戻す)。
set -u

file=""; old=""; new=""; case_name=""; munit=""; skip_baseline=0
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file=${2:?}; shift 2 ;;
    --old) old=${2:?}; shift 2 ;;
    --new) new=${2:?}; shift 2 ;;
    --case) case_name=${2:?}; shift 2 ;;
    --munit) munit=${2:?}; shift 2 ;;
    --skip-baseline) skip_baseline=1; shift ;;
    *) echo "teeth-check: 知らない引数: $1" >&2; exit 2 ;;
  esac
done
for v in file old new case_name; do
  eval "[ -n \"\$$v\" ]" || { echo "teeth-check: --${v/_name/} が必要" >&2; exit 2; }
done
[ -f "$file" ] || { echo "teeth-check: $file が無い" >&2; exit 2; }
[ -n "$munit" ] || munit=$(basename "$file")

# (1) 細工の当て先が一意か。**ここで落とすのが行番号ずれ対策の本体。**
# 数えるのは行ではなく**出現回数** (複数行にまたがる当て先も渡せるように python で数える)。
n=$(python3 -c 'import sys,pathlib; print(pathlib.Path(sys.argv[1]).read_text().count(sys.argv[2]))' "$file" "$old")
if [ "${n:-0}" -ne 1 ]; then
  echo "teeth-check: 細工の当て先 '$old' が $file に ${n:-0} 箇所 (1 箇所でなければ細工しない)" >&2
  echo "             0 なら文字列が違う。2 以上なら前後を足して一意にする。" >&2
  echo "             **行番号での指定はしません** (行がずれて細工が当たらない実例があります)。" >&2
  exit 2
fi

# case 名が実在するか。**打ち間違いを mvn 2 回のあとに気付かないため。**
# 実装側を壊すときは case は --munit 側にあるので、そちらを探す。
casefile=$file
case "$file" in *munit*) : ;; *) casefile=$(ls src/test/munit/"$munit" 2>/dev/null || echo "") ;; esac
if [ -n "$casefile" ] && [ -f "$casefile" ] && grep -q 'munit:test' "$casefile"; then
  grep -qF "name=\"$case_name\"" "$casefile" || {
    echo "teeth-check: case '$case_name' が $casefile に無い。名前を確かめてください。" >&2
    grep -oE 'munit:test name="[^"]+"' "$casefile" | sed 's/^/             ある case: /' >&2
    exit 2
  }
fi

backup=$(mktemp); cp "$file" "$backup"
restore() { cp "$backup" "$file"; rm -f "$backup"; }
trap restore EXIT INT TERM

# `timeout` は Windows (Git Bash) では GNU のものが無く、PATH の System32 にある
# **別物の timeout.exe** (指定秒だけ待つコマンド) が当たって壊れます。GNU のものがあるときだけ使う。
if timeout --version >/dev/null 2>&1; then TIMEOUT="timeout 900"; else TIMEOUT=""; fi
run() { $TIMEOUT mvn -q clean test -Dmunit.test="$munit" 2>&1; }

# (2) 細工前は緑か。赤いまま細工しても、赤い理由が細工とは限らない。
if [ "$skip_baseline" -eq 0 ]; then
  base=$(run); brc=$?
  bsum=$(printf '%s\n' "$base" | grep -oE 'Tests run: [0-9]+ - Failed: [0-9]+ - Errors: [0-9]+' | tail -1)
  if [ "$brc" -ne 0 ] || [ -z "$bsum" ] || ! printf '%s' "$bsum" | grep -q 'Failed: 0 - Errors: 0'; then
    echo "teeth-check: 細工前が緑ではない (exit $brc / ${bsum:-集計行が出ていない})" >&2
    echo "             先に緑にしてください。赤いまま細工しても牙は示せません。" >&2
    exit 2
  fi
  echo "teeth-check: 細工前 ok ($bsum)"
fi

# (3) 細工を当て、当たったことを表示する。
python3 - "$file" "$old" "$new" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
# **差分で出す。** `grep "$new"` だと元から同じ文字列がある行まで並び、どこに当たったか分からない
# (実測: 別の case が同じ sample を読んでいて 4 行出た)。
echo "teeth-check: 細工が当たった箇所 (差分):"
diff -u "$backup" "$file" | grep -E '^[-+][^-+]' | sed 's/^/  /'

after=$(run); arc=$?
asum=$(printf '%s\n' "$after" | grep -oE 'Tests run: [0-9]+ - Failed: [0-9]+ - Errors: [0-9]+' | tail -1)
hit=$(printf '%s\n' "$after" | grep -F "FAILURE - test: $case_name" | head -1)

if [ -z "$asum" ]; then
  echo "teeth-check: 集計行 (Tests run: ...) が出ていません。exit $arc" >&2
  echo "             テストに入る前に落ちています (前処理の例外、ビルド失敗)。" >&2
  echo "             **狙った検査は 1 度も走っていないので、牙は示せていません。**" >&2
  printf '%s\n' "$after" | tail -15 >&2
  exit 2
fi
# **順序が大事。** 「1 件も落ちなかった」と「別の case が落ちた」は原因も直し方も違うので、
# 先に集計を見る (実測: doc:name だけ壊したとき Failed: 0 なのに「別の case が落ちた」と言っていた)。
if printf '%s' "$asum" | grep -q 'Failed: 0 - Errors: 0'; then
  echo "teeth-check: 細工しても 1 件も落ちません ($asum)" >&2
  echo "             → **このテストに牙がありません。** 壊した箇所を assert が読んでいません。" >&2
  echo "             期待値そのもの (readUrl の参照先、equalTo の値、読む変数名) を壊してください。" >&2
  exit 2
fi
if [ -z "$hit" ]; then
  echo "teeth-check: 落ちたのは '$case_name' ではありません ($asum)" >&2
  echo "             **exit が非ゼロになったことを牙の証拠にしない。** 実際に落ちたのはこれです:" >&2
  printf '%s\n' "$after" | grep -E 'FAILURE - test:|ERROR - test:' | sed 's/^/               /' >&2
  echo "             狙った case を通る箇所を壊すか、先に落ちている前処理を直してください。" >&2
  exit 2
fi

echo "teeth-check: 牙あり — $case_name が失敗した ($asum)"
echo "  $hit"
exit 0
