# MuleSoft 公式ツールとの組み合わせ (付属情報)

2026-09-05 時点。出典は MuleSoft Developer Portal (https://dev-portal.mulesoft.com) と
GitHub https://github.com/mulesoft/mulesoft-dx (Apache-2.0)。

> ポータルの `llms.txt` / `AGENTS.md` / `registry.json` は **WebFetch など要約系ツールで読まない**。
> 構造が切り詰められる。`curl` で生のまま取る (ポータル自身がそう指示している)。

## 1. MuleSoft DX MCP Server

- ページ: https://dev-portal.mulesoft.com/mcps/mulesoft-mcp-server.html
- 公式ドキュメント: https://docs.mulesoft.com/mulesoft-mcp-server/
- 形: stdio、`npx -y mulesoft-mcp-server start` (npm 1.3.x)
- 認証: **Connected App (acts on its own behalf)** の Client ID / Secret を環境変数で渡す
  `ANYPOINT_CLIENT_ID`, `ANYPOINT_CLIENT_SECRET`, `ANYPOINT_REGION` (PROD_US / PROD_EU / PROD_CA / PROD_JP)
- 前提: Node.js、JDK (ローカル実行時)、`generate_mule_flow` と `generate_api_spec` は組織で Generative AI を有効化していること
- このプラグインの `.mcp.json` に設定済み。環境変数を export すれば動く。

ツール (21) とループでの位置づけ:

| ツール | 使うループ | 使い方 |
|---|---|---|
| `create_mule_project` | 計画 (T-001 の下準備) | 新規プロジェクトの骨格。`/mule-init` の前でも後でもよい |
| `generate_mule_flow` | 実行 (Green の補助) | 自然言語からフロー XML を生成。**生成物は仮説**で、MUnit が通るまで正しさは無い。Red を先に書いてから使う |
| `generate_api_spec`, `create_api_spec_project` | 意図 (手順 3) | RAML/OAS の草稿づくり。承認前の下書きに使う |
| `run_local_mule_application` | 実行 (段 2〜3) | ローカル起動。MUnit より遅いので契約テストや手動確認用 |
| `search_asset`, `create_and_manage_assets` | 意図 / 計画 | 既存 API との重複確認、Exchange への公開 |
| `list_api_instances`, `create_and_manage_api_instances`, `manage_api_instance_policy` | ゲート 3 の後 | API Manager 登録とポリシー。人が押した後の作業 |
| `deploy_mule_application`, `update_mule_application` | **人のゲート 3** | プラグインからは呼ばない。permissions で deny 相当の扱い |
| `list_applications`, `get_platform_insights`, `get_reuse_metrics` | 維持 | 週次の振り返り |
| `create_mcp_server` | 別用途 | Mule で MCP サーバーを作るとき |
| `*_runtime_fabric` | 別用途 | 基盤担当 |
| `manage_flex_gateway_policy_project`, `get_flex_gateway_policy_example` | 別用途 | PDK ポリシー開発 |

注意: `generate_mule_flow` は `originalPrompt` に **利用者の原文** を要求する。`/mule-start` が要約した文を渡すと品質が落ちるので、docs/spec/<name>.md に残した読み上げ文を渡す。

## 2. MuleSoft Platform MCP Server

- ページ: https://dev-portal.mulesoft.com/mcps/mulesoft-platform.html
- 形: streamable-http、`https://omni.mulesoft.com/mcp/` (0.1.0)
- 認証: 最初に `login` ツールを引数なしで呼ぶと対話ログインになる。Bearer (ユーザー) か OAuth2 (Connected App)
- 68 ツール。ポリシー、ガバナンス、Omni Gateway、API カタログ、モニタリング、コスト、エージェント/LLM カタログ
- 注意: ID は UUID 形式で渡す (表示名は不可)。ページングは最初のページで答えを組み立て、自動で全部は取らない。リージョンは US/EU/CA/JP/IN/AU
- このプラグインの `.mcp.json` に設定済み。

ループでの位置づけ: **ゲート 3 の後と、維持フェーズ**。実装ループでは使わない。
- 本番デプロイ後のポリシー適用 → 公式スキル `secure-api` / `apply-policy-to-api-instance` と組む
- 週次の振り返り → モニタリングとコストのツール

## 3. Platform Assistant (メタスキル)

- ページ: https://dev-portal.mulesoft.com/skills/platform-assistant.html
- 導入: `npx skills add https://github.com/mulesoft/mulesoft-dx/ --skill platform-assistant`
- 何か: ポータルの `llms.txt` → `AGENTS.md` → `registry.json` を辿って、公開 API 仕様 (OAS 30 本超)、JTBD 形式の公式スキル、`x-origin` (パラメータの値を別 API から動的に引く仕組み) を発見するための入口
- **このプラグインに同梱** (`skills/platform-assistant/`、Apache-2.0)。原本は portal-url をコンテキストから受け取る前提なので、同梱版は冒頭に URL を追記している

ループでの位置づけ: 意図ループの「事実は人に聞かず自分で調べる」の調べ先。既存 API の有無、認証方式、環境 ID の取り方はここから辿る。

## 4. mulesoft-dx の公式スキル群

同じリポジトリに 2 系統ある。`scripts/setup-deps.sh` が主要なものを入れる。

### skills/mule-development (npm: @salesforce/mulesoft-vibes-skills 1.9.0)

| スキル | ループでの位置づけ |
|---|---|
| `build-mule-integration` | 実行 (Green)。コネクタ発見と XML 生成。Anypoint CLI v4 + DX plugin が要る。**mule-tdd の Red の後に使う** |
| `manage-global-configurations` | 実行。global.xml の整備。Refactor で使う |
| `generate-bat-tests` | 段 3。デプロイ後のブラックボックス契約テスト (BAT CLI)。MUnit の代わりではない |
| `secure-mule-app` | 実行。secure properties |
| `manage-api-version`, `upgrade-mule-app` | 維持 |
| `generate-doc-description` | Refactor。doc:description の付与 |
| `build-agent-broker-project`, `translate-agent-broker-old-to-new-project` | 別用途 (Agent Network) |
| `develop-pdk-policy`, `pdk-*` | 別用途 (Flex Gateway ポリシー) |
| `create/update/delete/execute-mule-run-config`, `run-system-diagnostics` | ACB (VS Code) 専用の Language Model Tool を前提にしており、Claude Code 単体では動かない |

### skills/ (JTBD 形式、プラットフォーム操作)

`secure-api`, `apply-policy-to-api-instance`, `secure-mcp-server`, `secure-agent`, `setup-service-scanner`,
`run-service-scan-and-view-results`, `discover-portal-apis`, `request-api-access`, `curate-portal-assets`,
`manage-portal-*`。すべてゲート 3 の後か、API Experience Hub の運用向け。

### 関連: API 仕様の検証

`/plugin marketplace add machaval/api-spec-skills` で `api-spec-validator` が入る。意図ループの手順 3 で RAML/OAS を Anypoint CLI のガバナンスルールで検証するのに使える。

## 5. プロジェクト作成 (Maven のライブラリ取得が失敗する問題)

手で `pom.xml` を書いた Mule プロジェクトは、mule-maven-plugin の `<extensions>true</extensions>`、
`mule-application` パッケージング、Exchange / MuleSoft のリポジトリ定義、`mule-artifact.json` のどれかが欠けて
ライブラリ取得に失敗する。Studio / ACB と同じ骨格を作る経路は 3 つあり、`/mule-init` は 1 を使う。

| 経路 | コマンド | 備考 |
|---|---|---|
| 1. Anypoint CLI v4 DX plugin | `anypoint-cli-v4 dx mule project create <name> --group-id <g> --mule-version 4.9.0 --dependencies "<GAV,...>"` | 手元で検証済み (2026-09-05)。`--skip-environment` は 1.0.3 には無い |
| 2. DX MCP Server | `create_mule_project` (projectPath, projectName) | 1 と同じ骨格。MCP 設定と Connected App が要る |
| 3. 公式スキル `build-mule-integration` | Step 8 で内部的に 1 を呼ぶ | コネクタ発見からやってくれるが、質問が多い |

導入: `npm i -g anypoint-cli-v4 && anypoint-cli-v4 plugins:install @salesforce/anypoint-cli-dx-mule-plugin`

生成される pom には **MUnit が入っていない**。これは Studio / ACB で作ったプロジェクトも同じで、
Studio は GUI で MUnit テストを作った時点で初めて追加する。`template/scripts/add-munit.sh` が
munit-runner / munit-tools / munit-maven-plugin を足す。字下げがタブ (Studio) でもスペース (CLI) でも動き、
挿入できなければ exit 1 で落ちる。MUnit の版は maven-metadata から最新を取る
(Mule 4.12 に MUnit 3.4 系を載せると `Cannot create embedded container` で起動しない)。
検証済み: Studio 生成 finance-api (Mule 4.12.2) と CLI 生成 order-sapi (4.9.0) の両方で Red/Green 成立。

MUnit の絞り込みは `-Dtest=` ではなく **`-Dmunit.test=<テストファイル名>`**。

Enterprise コネクタ (SAP、Salesforce の一部など) を使うときは `~/.m2/settings.xml` に Exchange の認証 (`anypoint-exchange-v2` の server 定義) が要る。無いと 401 でライブラリ取得が止まる。

## 6. 使い分けの原則

- **公式ツールは「生成」を速くし、mule-loop は「判定」を握る。** `generate_mule_flow` や `build-mule-integration` が何を出しても、done_when と MUnit が通るまでは仮説。
- **デプロイ系は人のゲート 3 の後。** `.mcp.json` に入れてはあるが、`mule-run` は呼ばない。
- **要約ツールでポータルを読まない。** `curl -s https://dev-portal.mulesoft.com/registry.json | jq` のように生で取る。
