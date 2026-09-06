#!/usr/bin/env bash
# context/deployment/sandbox.yaml から mule-maven-plugin のデプロイ設定を pom.xml に入れる。
# 入れるのは cloudhub2Deployment か runtimeFabricDeployment のどちらか 1 つと、Exchange の distributionManagement。
# 秘密は書かない (${env.ANYPOINT_CLIENT_ID} / ${env.ANYPOINT_CLIENT_SECRET} を参照する)。
# Studio の pom はタブ字下げ、CLI はスペース字下げなので正規表現で受け、最後に「入ったか」を検証する。
set -eu
yaml=context/deployment/sandbox.yaml
[ -f pom.xml ] || { echo "deploy-config: pom.xml がありません" >&2; exit 2; }
[ -f "$yaml" ] || { echo "deploy-config: $yaml がありません (人が書く)" >&2; exit 2; }
python3 - "$yaml" <<'PY'
import re, sys, pathlib
y = {}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    line = line.split("#", 1)[0].rstrip()
    m = re.match(r'^([a-z_]+):\s*(.*)$', line)
    if m: y[m.group(1)] = m.group(2).strip().strip('"')
pom = pathlib.Path("pom.xml"); s = pom.read_text()
kind = y.get("kind", "cloudhub2")
gid = re.search(r'<groupId>([^<]+)</groupId>', s).group(1)
aid = re.search(r'<artifactId>([^<]+)</artifactId>', s).group(1)
if not re.fullmatch(r'[0-9a-f-]{36}', gid):
    sys.exit(f"deploy-config: groupId が組織 ID (UUID) ではありません: {gid}\n"
             "  CH2 / RTF は Exchange 経由でデプロイするため groupId は Anypoint の組織 ID である必要があります。")
app = y.get("application_name") or aid
if "cloudhub2Deployment" in s or "runtimeFabricDeployment" in s:
    print("deploy-config: 既にデプロイ設定があります (何もしません)"); sys.exit(0)
auth = ("<connectedAppClientId>${env.ANYPOINT_CLIENT_ID}</connectedAppClientId>\n"
        "<connectedAppClientSecret>${env.ANYPOINT_CLIENT_SECRET}</connectedAppClientSecret>\n"
        "<connectedAppGrantType>client_credentials</connectedAppGrantType>")
common = (f"<uri>https://anypoint.mulesoft.com</uri>\n<provider>MC</provider>\n"
          f"<environment>{y['environment']}</environment>\n<target>{y['target']}</target>\n"
          f"<muleVersion>{y['mule_version']}</muleVersion>\n<applicationName>{app}</applicationName>\n"
          f"<replicas>{y.get('replicas','1')}</replicas>\n{auth}")
pub = f"<http><inbound><publicUrl>{y['public_url']}</publicUrl></inbound></http>" if y.get("public_url") else ""
if kind == "cloudhub2":
    block = (f"<cloudhub2Deployment>\n{common}\n<vCores>{y.get('vcores','0.1')}</vCores>\n"
             + (f"<deploymentSettings>{pub}</deploymentSettings>\n" if pub else "") + "</cloudhub2Deployment>")
elif kind == "rtf":
    block = (f"<runtimeFabricDeployment>\n{common}\n<deploymentSettings>\n"
             f"<resources><cpu><reserved>{y.get('cpu_reserved','500m')}</reserved></cpu>"
             f"<memory><reserved>{y.get('memory_reserved','700Mi')}</reserved></memory></resources>\n"
             f"{pub}\n</deploymentSettings>\n</runtimeFabricDeployment>")
else:
    sys.exit(f"deploy-config: kind は cloudhub2 か rtf: {kind}")
# mule-maven-plugin の <configuration> の直後に入れる。無ければ作る。
m = re.search(r'<artifactId>mule-maven-plugin</artifactId>.*?(<configuration>)', s, re.S)
if m:
    s = s[:m.end(1)] + "\n" + block + s[m.end(1):]
else:
    m = re.search(r'(<artifactId>mule-maven-plugin</artifactId>.*?<extensions>true</extensions>)', s, re.S)
    if not m: sys.exit("deploy-config: pom に mule-maven-plugin が見つかりません")
    s = s[:m.end(1)] + "\n<configuration>\n" + block + "\n</configuration>" + s[m.end(1):]
if "<distributionManagement>" not in s:
    dm = ("<distributionManagement>\n<repository>\n<id>anypoint-exchange-v3</id>\n<name>Exchange</name>\n"
          f"<url>https://maven.anypoint.mulesoft.com/api/v3/organizations/{gid}/maven</url>\n"
          "<layout>default</layout>\n</repository>\n</distributionManagement>\n")
    s = s.replace("</project>", dm + "</project>")
pom.write_text(s)
chk = pom.read_text()
tag = "cloudhub2Deployment" if kind == "cloudhub2" else "runtimeFabricDeployment"
if tag not in chk or "distributionManagement" not in chk:
    sys.exit("deploy-config: 書き込んだはずの設定が pom にありません")
print(f"deploy-config: {tag} と distributionManagement を pom.xml に入れました (app={app}, target={y['target']})")
PY
xmllint --noout pom.xml 2>/dev/null || { echo "deploy-config: pom.xml が壊れました。git checkout pom.xml で戻してください" >&2; exit 2; }
grep -q 'anypoint-exchange-v3' ~/.m2/settings.xml 2>/dev/null || \
  echo "deploy-config: 注意: ~/.m2/settings.xml に <server><id>anypoint-exchange-v3</id> が無いと mvn deploy が 401 になります (docs/mulesoft-tools.md)" >&2
