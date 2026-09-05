#!/usr/bin/env bash
# mule-loop が借りる外部スキルと MCP の前提を入れる。何度実行しても安全。
set -u
say() { printf '\n== %s\n' "$*"; }

say "1. mattpocock-skills (意図ループの grilling / domain-modeling)"
claude plugin install mattpocock-skills@claude-plugins-official 2>&1 | tail -1

say "2. MuleSoft 公式スキル (mulesoft-dx, Apache-2.0)"
# 実行ループで使う開発系と、平台操作系。必要なものだけ選んで増減してよい。
for s in build-mule-integration manage-global-configurations generate-bat-tests \
         secure-mule-app manage-api-version upgrade-mule-app \
         secure-api apply-policy-to-api-instance; do
  npx -y skills add https://github.com/mulesoft/mulesoft-dx/ --skill "$s" -y 2>&1 | tail -1
done

say "3. MCP の前提"
command -v node >/dev/null || echo "node が無い。mulesoft-mcp-server は npx で動くので Node.js 18+ が必要"
[ -n "${ANYPOINT_CLIENT_ID:-}" ] || cat <<'MSG'
ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET が未設定。
Connected App (acts on its own behalf) を作り、~/.bashrc などで export する。
必要スコープは docs/mulesoft-tools.md を参照。未設定でも mulesoft-mcp-server 以外は動く。
MSG

say "4. ローカル検証ツール"
for t in mvn dw xmllint gh; do printf '%-8s %s\n' "$t" "$(command -v $t >/dev/null && echo ok || echo '無い')"; done
