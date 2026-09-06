#!/usr/bin/env bash
# Studio / ACB / dx mule project create が作った pom.xml に MUnit を足す。既にあれば何もしない。
# 字下げがタブでもスペースでも動く。挿入できなければ exit 1 で落ちる (黙って成功しない)。
# 使い方: scripts/add-munit.sh [pom.xml] [munit.version]
set -eu
pom="${1:-pom.xml}"
# MUnit の版は指定が無ければ最新を取りにいく。Mule 4.12 は MUnit 3.4 系だと
# java.lang.module.ResolutionException (plexus.utils の衝突) で起動しない。
ver="${2:-}"
if [ -z "$ver" ]; then
  ver=$(curl -s --max-time 10 https://repository.mulesoft.org/nexus/repository/releases/com/mulesoft/munit/tools/munit-maven-plugin/maven-metadata.xml \
        | grep -oE "<release>[^<]*" | sed "s/<release>//" | head -1)
  : "${ver:=3.7.4}"
fi
[ -f "$pom" ] || { echo "pom が見つかりません: $pom" >&2; exit 1; }
grep -q munit-maven-plugin "$pom" && { echo "MUnit は設定済み: $pom"; exit 0; }
python3 - "$pom" "$ver" <<'PY'
import sys,re
p,ver=sys.argv[1],sys.argv[2]
s=open(p).read(); orig=s

def indent_of(tag):
    m=re.search(r'^([ \t]*)</%s>'%tag, s, re.M)
    return m.group(1) if m else "    "

def unit(i):                      # 1 段分の字下げ (タブなら \t、スペースなら 4 個)
    return "\t" if "\t" in i else "    "

# 1) properties に munit.version
ip=indent_of("properties"); u=unit(ip)
if not re.search(r'^[ \t]*</properties>', s, re.M):
    # properties そのものが無い場合は project 直下に作る
    s=re.sub(r'(</(?:name|version|packaging)>\n)',
             r'\1\n\t<properties>\n\t\t<munit.version>%s</munit.version>\n\t</properties>\n'%ver, s, count=1)
else:
    s=re.sub(r'^([ \t]*)</properties>'%(),
             lambda m: "%s%s<munit.version>%s</munit.version>\n%s</properties>"%(m.group(1),unit(m.group(1)),ver,m.group(1)),
             s, count=1, flags=re.M)

# 2) dependencies に munit-runner / munit-tools
dep_tpl = """{i}{u}<dependency>
{i}{u}{u}<groupId>com.mulesoft.munit</groupId>
{i}{u}{u}<artifactId>{a}</artifactId>
{i}{u}{u}<version>${{munit.version}}</version>
{i}{u}{u}<classifier>mule-plugin</classifier>
{i}{u}{u}<scope>test</scope>
{i}{u}</dependency>
"""
if re.search(r'^[ \t]*</dependencies>', s, re.M):
    def add_deps(m):
        i=m.group(1); u=unit(i)
        blocks="".join(dep_tpl.format(i=i,u=u,a=a) for a in ("munit-runner","munit-tools"))
        return blocks+i+"</dependencies>"
    s=re.sub(r'^([ \t]*)</dependencies>', add_deps, s, count=1, flags=re.M)
else:
    blocks="".join(dep_tpl.format(i="\t",u="\t",a=a) for a in ("munit-runner","munit-tools"))
    s=re.sub(r'(^[ \t]*</build>\n)', "\n\t<dependencies>\n"+blocks+"\t</dependencies>\n"+r'\1', s, count=1, flags=re.M)

# 3) build/plugins に munit-maven-plugin
plug_tpl = """{i}{u}<plugin>
{i}{u}{u}<groupId>com.mulesoft.munit.tools</groupId>
{i}{u}{u}<artifactId>munit-maven-plugin</artifactId>
{i}{u}{u}<version>${{munit.version}}</version>
{i}{u}{u}<executions>
{i}{u}{u}{u}<execution>
{i}{u}{u}{u}{u}<id>test</id>
{i}{u}{u}{u}{u}<phase>test</phase>
{i}{u}{u}{u}{u}<goals><goal>test</goal><goal>coverage-report</goal></goals>
{i}{u}{u}{u}</execution>
{i}{u}{u}</executions>
{i}{u}{u}<configuration>
{i}{u}{u}{u}<runtimeVersion>${{app.runtime}}</runtimeVersion>
{i}{u}{u}{u}<dynamicPorts><dynamicPort>http.port</dynamicPort></dynamicPorts>
{i}{u}{u}{u}<coverage>
{i}{u}{u}{u}{u}<runCoverage>true</runCoverage>
{i}{u}{u}{u}{u}<formats><format>console</format><format>html</format></formats>
{i}{u}{u}{u}</coverage>
{i}{u}{u}</configuration>
{i}{u}</plugin>
"""
m=re.search(r'^([ \t]*)</plugins>', s, re.M)
if not m: print("pom に <plugins> がありません", file=sys.stderr); sys.exit(1)
i=m.group(1); u=unit(i)
s=s[:m.start()]+plug_tpl.format(i=i,u=u)+i+"</plugins>"+s[m.end():]

# 4) 検証してから書く。入っていなければ落とす
need=("munit.version","munit-runner","munit-tools","munit-maven-plugin")
missing=[n for n in need if n not in s]
if missing or s==orig:
    print("MUnit を挿入できませんでした: %s (pom の構造を確認してください)"%(", ".join(missing) or "変更なし"), file=sys.stderr)
    sys.exit(1)
open(p,'w').write(s)
PY
mkdir -p src/test/munit src/test/resources
echo "MUnit $ver を追加: $pom"
