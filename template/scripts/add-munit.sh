#!/usr/bin/env bash
# dx mule project create / Studio / ACB が作った pom.xml に MUnit を足す。既にあれば何もしない。
# 使い方: scripts/add-munit.sh [pom.xml] [munit.version]
set -eu
pom="${1:-pom.xml}"; ver="${2:-3.4.0}"
grep -q munit-maven-plugin "$pom" && { echo "MUnit は設定済み: $pom"; exit 0; }
python3 - "$pom" "$ver" <<'PY'
import sys,re
p,ver=sys.argv[1],sys.argv[2]
s=open(p).read()
prop=f"        <munit.version>{ver}</munit.version>\n    </properties>"
s=s.replace("    </properties>",prop,1)
deps="""        <dependency>
            <groupId>com.mulesoft.munit</groupId>
            <artifactId>munit-runner</artifactId>
            <version>${munit.version}</version>
            <classifier>mule-plugin</classifier>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>com.mulesoft.munit</groupId>
            <artifactId>munit-tools</artifactId>
            <version>${munit.version}</version>
            <classifier>mule-plugin</classifier>
            <scope>test</scope>
        </dependency>
    </dependencies>"""
s=s.replace("    </dependencies>",deps,1)
plug="""            <plugin>
                <groupId>com.mulesoft.munit.tools</groupId>
                <artifactId>munit-maven-plugin</artifactId>
                <version>${munit.version}</version>
                <executions>
                    <execution>
                        <id>test</id>
                        <phase>test</phase>
                        <goals><goal>test</goal><goal>coverage-report</goal></goals>
                    </execution>
                </executions>
                <configuration>
                    <runtimeVersion>${app.runtime}</runtimeVersion>
                    <dynamicPorts><dynamicPort>http.port</dynamicPort></dynamicPorts>
                    <coverage>
                        <runCoverage>true</runCoverage>
                        <formats><format>console</format><format>html</format></formats>
                    </coverage>
                </configuration>
            </plugin>
        </plugins>"""
s=s.replace("        </plugins>",plug,1)
open(p,'w').write(s)
PY
mkdir -p src/test/munit src/test/resources
echo "MUnit $ver を追加: $pom"
