---
name: mule-setup
description: mule-loop が借りる外部スキル (mattpocock-skills、MuleSoft 公式スキル) と MCP サーバーの前提を、各メンバーの環境に入れる。初回 1 回と、公式スキルを更新したいときに使う。
---

`${CLAUDE_PLUGIN_ROOT}/scripts/setup-deps.sh` を実行し、結果を表にして伝える。

その後:
1. `ANYPOINT_CLIENT_ID` が無ければ、Connected App の作り方を 3 行で案内する (docs/mulesoft-tools.md の「認証」を読む)。作れるのは組織管理者なので、無ければ誰に頼むかを聞く。
2. `mvn` が無ければ、それ無しでは検証の段 2, 3 が動かず TDD が成立しないことを明言する。
3. 最後に「次は `/mule-init`」と案内する。
