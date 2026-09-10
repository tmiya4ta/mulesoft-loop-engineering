# Batch / MCP / A2A (`kind` が `api` 以外のとき)

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

1〜9 節と `template/reference/` は `kind: api` (RAML + APIkit) を前提にしている。ここは最小限の方向づけで、
このループでの実測 ([G]) はまだ無い。**[S] は利用者の `mulesoft-app-development` スキルに書かれていた既知情報で、
根拠は「そのスキルに書いてある」までであり、[G] のような実測ではない。**

- **Batch**: `pom.xml` / MUnit の骨格はそのまま使える (`kind: api` と同じ手順で作る)。RAML と APIkit は無い。
  `batch:job` の設定を `configuration-properties` の YAML から読むとき、`blockSize` / `maxConcurrency` は
  **数値としてクォートしない** (2 節。クォートすると文字列になって壊れる)。MERGE (upsert) は `db:update` を使う
  (`db:insert` / `db:execute-script` は `input-parameters` が使えない。6 節)。まだ専用の `template/reference/` 雛形は
  無いので、書く前に困ったら gotchas → スキル (`platform-assistant` 経由の `mulesoft-app-development`) →
  マニュアルの順で調べる。[S]
- **MCP サーバー**: `<mcp:server>` という要素は **存在しない** (main の XML に書くとバリデーションエラー)。
  `mcp:server-config` は `global-config.xml` に 1 つ置き、ツールは別ファイル (`impl/*.xml` など) に
  **1 tool = 1 flow** (`<mcp:tool-listener config-ref="..." name="...">` + `<mcp:parameters-schema>` + `<mcp:responses>`) で書く。
  動作確認は Server-Sent Events で、`Accept: text/event-stream` ヘッダーが無いと応答が返らない
  (応答は `event: message\ndata: {...}` の形)。[S]
- **A2A (Agent Fabric の Agent Network)**: **このプラグインでは作らない。** `agentNetwork.yaml` / `.agent` ファイルという
  別のプロジェクト形式で、pom.xml を持つ通常の Mule アプリではない。`agent-network` スキルと
  `deploy-agent-network-v1` / `deploy-agent-network-v2` スキルに任せる。`/mule-init` は `kind: a2a` を選ぶと
  その案内だけをして終了し、Mule プロジェクトを作らない。
