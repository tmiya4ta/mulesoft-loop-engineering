#!/usr/bin/env bash
# dx mule project create は mule-maven-plugin を 4.7.0 に固定するが、これは Mule 4.12 系と非互換で
#   NoSuchMethodError: MuleRuntimeFeature.isEnabled(java.util.Optional)
# が出てビルドが通らない。app.runtime に合わせて版を上げる。何度実行しても安全。
set -eu
pom="${1:-pom.xml}"
rt=$(sed -n 's/.*<app.runtime>\(.*\)<\/app.runtime>.*/\1/p' "$pom" | head -1)
cur=$(sed -n 's/.*<mule.maven.plugin.version>\(.*\)<\/mule.maven.plugin.version>.*/\1/p' "$pom" | head -1)
[ -z "$rt" ] && { echo "app.runtime が読めません: $pom" >&2; exit 1; }
minor=$(printf '%s' "$rt" | cut -d. -f2)
want=4.10.1                              # Studio 4.12 が使う版。4.12 系で動作確認済み
[ "${minor:-0}" -lt 10 ] && want="$cur"  # 4.9 以下は CLI の既定のままでよい
if [ -n "$cur" ] && [ "$cur" != "$want" ]; then
  sed -i "s|<mule.maven.plugin.version>$cur<|<mule.maven.plugin.version>$want<|" "$pom"
  echo "mule-maven-plugin: $cur → $want (Mule $rt に合わせて更新)"
else
  echo "mule-maven-plugin: $cur のまま (Mule $rt)"
fi
