# mule-loop

MuleSoft API を Claude Code の **ループエンジニアリング** で作るためのプラグイン兼テンプレート。
MuleSoft を知らない人でも `/mule-start` の対話だけで、仕様 → 受け入れ条件 → ゴール台帳 → 実装 → PR まで 1 コンソールで進める。

考え方は [docs/methodology.md](docs/methodology.md)。実装は TDD (Red → Green → Refactor) で進める。

## 導入 (チームの各メンバー)

```bash
# 1. このリポジトリをマーケットプレイスとして登録し、プラグインを入れる
claude plugin marketplace add tmiya4ta/mulesoft-loop-engineering   # git から
#   ローカルなら: claude plugin marketplace add /path/to/mulesoft-loop-engineering
claude plugin install mule-loop@mule-loop-marketplace

# 2. 依存 (mattpocock-skills、MuleSoft 公式スキル、MCP の前提確認)
claude
> /mule-setup
```

登録せずに試すなら:

```bash
claude --plugin-dir /path/to/mulesoft-loop-engineering
```

## 使い方

```bash
cd my-order-sapi           # Mule プロジェクト (新規でも既存でも)
claude
> /mule-init               # CLAUDE.md, tasks/, samples/, api/, scripts/ を配置 (1 回だけ)
> /mule-start 注文の状態を返す API
```

あとは質問に答えるだけ。止める位置を変えたいとき:

| コマンド | どこまで進むか |
|---|---|
| `/mule-start --spec-only` | 仕様と受け入れ条件を作って承認をとるまで |
| `/mule-start --plan-only` | 台帳 `tasks/T-*.md` を切るまで |
| `/mule-start` | 実装、レビュー、PR 作成まで (マージは人) |
| `/mule-run` | 台帳の未完了ゴールだけ回す。中断からの再開 |
| `/mule-run T-003` | 1 件だけ |
| `/mule-run --parallel 3` | 3 件まで並列 |
| `/mule-setup` | 外部スキルと MCP の前提を入れる (初回) |
| `/mule-tdd` | 実行エージェントが従う Red → Green → Refactor の規律。人が手で実装するときも使える |

## 中身

```
.claude-plugin/   plugin.json / marketplace.json
skills/
  mule-setup/     外部依存の導入 (scripts/setup-deps.sh)
  mule-init/      テンプレート配置
  mule-tdd/       TDD の規律 (実行エージェントが必ず従う)
  platform-assistant/  MuleSoft 公式メタスキルを同梱 (Apache-2.0)
  mule-start/     意図 → 計画 → 実行 を通す入口 (進捗エージェントの手順書)
  mule-run/       計画・実行ループだけ (再開用)
agents/
  mule-executor.md  ゴール 1 件を done_when が通るまで回す (worktree 隔離)
  mule-reviewer.md  読み取り専用レビュー
hooks/hooks.json  編集のたびに scripts/quick-check.sh (数秒の検証)
template/         /mule-init が配る: CLAUDE.md, CONTEXT.md, tasks/, samples/, api/, scripts/done.sh, .claude/settings.json
.mcp.json         MuleSoft DX MCP Server (stdio) と Platform MCP Server (http)
docs/methodology.md
docs/mulesoft-tools.md  公式 MCP / スキルの一覧とループでの位置づけ
```

## MuleSoft 公式ツール

[docs/mulesoft-tools.md](docs/mulesoft-tools.md) に、DX MCP Server (21 ツール)、Platform MCP Server (68 ツール)、公式スキル群 (mulesoft-dx) の一覧と、どのループで使うかをまとめてある。MCP は `.mcp.json` で有効になる。DX MCP Server には Connected App の環境変数が要る。

```bash
export ANYPOINT_CLIENT_ID=...
export ANYPOINT_CLIENT_SECRET=...
export ANYPOINT_REGION=PROD_JP
```

## 人が押すのは 3 か所だけ

1. `/mule-start` が平文で読み上げる動作への「はい」
2. PR のマージ
3. 本番デプロイ (`anypoint-cli deploy` はプラグインが実行しない)

## 必要なツール

| ツール | 無いとどうなるか |
|---|---|
| Maven + Mule Maven Plugin | 段 2, 3 の検証が動かない (必須) |
| Anypoint CLI v4 + `@salesforce/anypoint-cli-dx-mule-plugin` | `/mule-init` がプロジェクト骨格を作れない。手書き pom はライブラリ取得に失敗する |
| `dw` CLI | DataWeave の秒単位検証が段 2 に落ちる |
| `xmllint` | Mule XML の即時検査が飛ぶ |
| `gh` | PR 作成が手動になる |
