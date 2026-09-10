#!/usr/bin/env bash
# 配備用の jar に「git が無視しているファイル」が入っていないか見る。**入っていたら止める。**
#
# なぜ必要か。`-DattachMuleSources` を付けると mule-maven-plugin は **プロジェクト全体を
# ファイルシステムから丸ごと** `META-INF/mule-src/` に入れます。**`.gitignore` は見られません。**
# 実測 (inventory2-api、2026-09-09): `.gitignore` 済みで DB パスワードを平文で持つ資格情報ファイルが
# そのまま jar に入りました。git には一度も入っていないので `git log -S` では見つかりません。
# jar は Exchange に上がって組織の全員から見えるので、**気付くのは配る側だけです。**
#
# `.gitignore` を秘密の防御に使えるのは git に対してだけ。**jar には別の検査が要る**、というのが
# ここの要点です。パターンで秘密を当てるのではなく **git が無視しているかどうか**で判定します
# (`credential` や `password` という名前でなくても引っかかるし、誤検知も少ない)。
#
# 使い方: bash scripts/jar-leak-check.sh [jar のパス]
#   省略すると target/*.jar を全部見ます。exit 0 = 混入なし / exit 2 = 混入あり (配らない)
#
# 限界: 見るのは「git が無視しているファイルが jar に入っているか」だけです。
# 追跡されているファイルの中に書かれた秘密は見ません (それは secret-leak の別の指紋で、
# `quick-check` と人のレビューが受け持ちます)。
set -u
# **リポジトリ直下に cd しません。** monorepo ではプロジェクトが git の直下ではないので
# (実測: inventory2-api の git 直下は mule-demos)、移動すると target/*.jar を見つけられません。
# `git check-ignore` は cwd 相対のパスで動くので、そのままで判定できます。

jars=()
if [ "$#" -gt 0 ]; then jars=("$@")
else for j in target/*.jar; do [ -f "$j" ] && jars+=("$j"); done; fi
[ "${#jars[@]}" -gt 0 ] || { echo "jar-leak-check: jar がありません (mvn package の前?)" >&2; exit 0; }

command -v unzip >/dev/null 2>&1 || { echo "jar-leak-check: unzip が無いので検査できません" >&2; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "jar-leak-check: git の外なので判定できません" >&2; exit 0; }

rc=0
for j in "${jars[@]}"; do
  # mule-src の中身をリポジトリ相対パスに直す (META-INF/mule-src/<アプリ名>/<相対パス>)
  paths=$(unzip -Z1 "$j" 2>/dev/null | sed -n 's|^META-INF/mule-src/[^/]*/||p' | grep -v '/$' || true)
  if [ -z "$paths" ]; then
    echo "jar-leak-check: $(basename "$j") に META-INF/mule-src/ は無い (attachMuleSources 無し)"
    continue
  fi
  # git が無視しているものだけを拾う。--stdin で 1 回で判定する (ファイル数が多いので)。
  # **空行を必ず落とす。** 1 行でも空だと `fatal: empty string is not a valid pathspec` で
  # 全体が exit 128 になり、`|| true` で飲むと「混入なし」と嘘をつきます (実測でそうなった)。
  # **exit を見て、0/1 以外は「判定できなかった」と言って止めます。** 黙って ok にしません。
  list=$(printf '%s\n' "$paths" | awk 'NF')
  n=$(printf '%s\n' "$list" | awk 'NF' | wc -l)
  leaked=$(printf '%s\n' "$list" | git check-ignore --stdin 2>&1); ci=$?
  if [ "$ci" -gt 1 ]; then
    rc=2
    { echo "jar-leak-check: $(basename "$j") を判定できませんでした (git check-ignore が exit $ci)"
      printf '%s\n' "$leaked" | head -3 | sed 's/^/  /'
      echo "  → 混入していないと断定できないので、配る前に人が確かめてください。" ; } >&2
    continue
  fi
  if [ "$ci" -eq 0 ] && [ -n "$leaked" ]; then
    rc=2
    {
      echo "jar-leak-check: $(basename "$j") に **git が無視しているファイル** が入っています。配らないでください。"
      printf '%s\n' "$leaked" | sed 's/^/  - /'
      echo "  → .gitignore は jar には効きません (-DattachMuleSources はファイルシステムを丸ごと入れる)。"
      echo "    秘密を持つファイルは**プロジェクトの外**に置く (例: ~/<app>-credential、パーミッション 600)。"
      echo "    この jar は削除して、ファイルを移してから作り直してください。"
    } >&2
  else
    echo "jar-leak-check: $(basename "$j") は ok (mule-src $n 件、git が無視しているものは無し)"
  fi
done
exit $rc
