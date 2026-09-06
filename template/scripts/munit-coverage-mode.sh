#!/usr/bin/env bash
# MUnit の本物のカバレッジ計測は Enterprise ランタイムでしか動かない (CE では警告のみで素通り)。
# EE が取得できるかを確かめ、できるときだけ pom に runtimeProduct と 100% ゲートを入れる。
set -u
pom="${1:-pom.xml}"
ver=$(sed -n 's/.*<app.runtime>\(.*\)<\/app.runtime>.*/\1/p' "$pom" | head -1); : "${ver:=4.12.2}"
if mvn -q -o dependency:get -Dartifact=com.mulesoft.mule.distributions:mule-ee-distribution-standalone:${ver}:zip >/dev/null 2>&1 \
   || mvn -q dependency:get -Dartifact=com.mulesoft.mule.distributions:mule-ee-distribution-standalone:${ver}:zip >/dev/null 2>&1; then
  echo "EE ランタイムを取得できました。MUnit カバレッジ 100% ゲートを有効にします。"
  grep -q runtimeProduct "$pom" || python3 - "$pom" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("<runtimeVersion>${app.runtime}</runtimeVersion>",
"<runtimeVersion>${app.runtime}</runtimeVersion>\n                    <runtimeProduct>MULE_EE</runtimeProduct>")
s=s.replace("<runCoverage>true</runCoverage>","""<runCoverage>true</runCoverage>
                        <failBuild>true</failBuild>
                        <requiredApplicationCoverage>100</requiredApplicationCoverage>
                        <requiredResourceCoverage>100</requiredResourceCoverage>
                        <requiredFlowCoverage>100</requiredFlowCoverage>""")
open(p,'w').write(s)
PY
  exit 0
fi
cat >&2 <<'MSG'
EE ランタイムを取得できません (CE)。MUnit のカバレッジ計測は EE 限定機能で、
CE では設定しても「Coverage is a EE only feature」の警告が出るだけで素通りします。
そのため pom には入れません。代わりに scripts/coverage-check.sh が
「全 flow に対応する MUnit がある」ことを構造的に保証します。

本物のカバレッジ率が要る場合は ~/.m2/settings.xml に MuleSoft Enterprise の
リポジトリ認証を足してから、このスクリプトを再実行してください。
MSG
exit 0
