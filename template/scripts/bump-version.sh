#!/usr/bin/env bash
# デプロイ前に pom の <version> のパッチ番号を 1 上げる。Exchange は同一版を上書きできない (knowledge/gotchas/deploy.md)。
# 使い方: bump-version.sh            → 1.0.3 → 1.0.4 (SNAPSHOT は外す)
set -eu
pom=pom.xml; [ -f $pom ] || { echo "bump-version: pom.xml がありません" >&2; exit 2; }
cur=$(python3 - <<'PY'
import re;s=open("pom.xml").read()
# project 直下の version (parent や dependency の version ではない): <artifactId> の後、<packaging> の前に現れる最初のもの
m=re.search(r'</artifactId>\s*<version>([^<]+)</version>',s); print(m.group(1) if m else "")
PY
)
[ -n "$cur" ] || { echo "bump-version: <version> が見つかりません" >&2; exit 2; }
base=${cur%-SNAPSHOT}; IFS=. read -r a b c <<<"$base"; c=${c:-0}
new="$a.${b:-0}.$((c+1))"
sed -i "0,/<version>$cur<\/version>/s//<version>$new<\/version>/" $pom
grep -q "<version>$new</version>" $pom || { echo "bump-version: 書き換えに失敗" >&2; exit 2; }
echo "bump-version: $cur → $new"
