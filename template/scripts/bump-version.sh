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
# **書き換えも python3 で行います。** `sed -i` は macOS (BSD sed) では引数が要り、`0,/re/` の
# アドレスは GNU sed にしかありません。どちらも「Linux では動くが Mac / Windows で落ちる」形です。
python3 - "$cur" "$new" <<'PY'
import sys
cur, new = sys.argv[1], sys.argv[2]
s = open("pom.xml").read()
open("pom.xml", "w").write(s.replace(f"<version>{cur}</version>", f"<version>{new}</version>", 1))
PY
grep -q "<version>$new</version>" $pom || { echo "bump-version: 書き換えに失敗" >&2; exit 2; }
echo "bump-version: $cur → $new"
