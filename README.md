# mule-loop

MuleSoft API を Claude Code の **ループエンジニアリング** で作るためのプラグイン兼テンプレート。
MuleSoft を知らない人でも `/mule-start` の対話だけで、仕様 → 受け入れ条件 → ゴール台帳 → 実装 → PR まで 1 コンソールで進める。

考え方は [docs/methodology.md](docs/methodology.md)。実装は TDD (Red → Green → Refactor) で進める。

> **v0.5.1** — PR #2 の実測を手順に反映: デプロイごとに版を上げる (`bump-version.sh`)、CH2 の公開 URL は API で付ける (`ch2-public-url.sh`)、ポリシーはゲートウェイの型 (`api.gateway`) で手順を分け、同梱スキルを先に読む。
> **v0.5.0** — 実装の先 (デプロイ、ポリシー) も台帳のゴール (`stage:`) にして同じループで回す。規律 (台帳の外で作業しない / マニュアルを読まない / 3 ブロックで締める) を UserPromptSubmit と Stop の hook に移し、長い会話で薄れないようにした。
> **v0.4.1** — 人に聞く場面を「最初の 1 回 + 4 つのゲート」に固定 (`context/decisions.yaml`)。途中の判断は既定で進めて承認時に仮定として一覧にする。
> **v0.4.0** — デプロイのループ (`/mule-deploy`) を追加。マージ後に Sandbox (CloudHub 2.0 / Runtime Fabric) へ置き、`samples/` の期待値で疎通を確かめ、失敗を学習ループに戻す。前版は `v0.3.2` タグ。

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
> /mule-init               # プロジェクト骨格 + context/, tasks/, budget.yaml を配置 (1 回だけ)
#   → ここで context/requirements/ に資料を置く (URL でもよい)
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
| `/mule-deploy` | マージ後に Sandbox へ置いて `samples/` で疎通確認。`--verify-only <url>` で確認だけ |
| `/mule-learn` | 2 回以上出た失敗を hook / 規則に昇格させる。`--share` で全員に共有 |
| `/mule-status` | **迷ったらこれ。** 今どこにいて次に何をすればよいかを 1 つだけ示す |

## 中身

```
.claude-plugin/   plugin.json / marketplace.json
skills/
  mule-setup/     外部依存の導入 (scripts/setup-deps.sh)
  mule-init/      テンプレート配置
  mule-tdd/       TDD の規律 (実行エージェントが必ず従う)
  mule-deploy/    デプロイのループ (Sandbox に置く → samples で疎通 → 失敗を学習へ)
  mule-learn/     学習ループ (失敗を数えて昇格・共有)
  mule-status/    現在地と次の一手のナビゲーション
  platform-assistant/  MuleSoft 公式メタスキルを同梱 (Apache-2.0)
  mule-start/     意図 → 計画 → 実行 を通す入口 (進捗エージェントの手順書)
  mule-run/       計画・実行ループだけ (再開用)
agents/
  mule-executor.md  ゴール 1 件を done_when が通るまで回す (worktree 隔離)
  mule-reviewer.md  読み取り専用レビュー
hooks/hooks.json  編集のたびに scripts/quick-check.sh (数秒の検証)、毎ターン scripts/loop-reminder.sh (規律の注入)、
                  応答の終わりに scripts/stop-guard.sh (3 ブロックで締めていなければ 1 回差し戻す)
knowledge/gotchas.md  共有ナレッジ (実行エージェントが毎回読む)
template/         /mule-init が配る:
  context/        前提の置き場所 (requirements / environment / deployment) + sources.yaml
  budget.yaml     コスト上限。/mule-run が配る前に確認
  context/deployment/authorizations.yaml  デプロイと実システム接続の許可 (人が書く)
  tasks/          ゴール台帳 (done_when + 試行ログ)
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh,
                  munit-coverage-mode.sh, run-log.sh, metrics.sh, cost-report.sh
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

## 始める前に人がやること

1. `context/requirements/` に資料を置く (または URL を `context/sources.yaml` に書く)。**ここが空だと `/mule-start` は始まらない。**
2. `context/environment/` に Mule 版や接続先の資料を置く。分からなければ空でよい (自動で調べて根拠つきで記録する)。
3. `budget.yaml` の上限を確認する。
4. Sandbox にデプロイさせたい場合だけ `context/deployment/authorizations.yaml` の `deploy.sandbox` を `allowed` にし、`context/deployment/sandbox.yaml` に置き場所 (cloudhub2 / rtf、target) を書く。

## 人が判断するのは 5 か所だけ

0. `/mule-start` の最初に `context/decisions.yaml` の空欄を **1 回にまとめて** 聞かれる (先に書いておけば聞かれない)。以降、承認まで質問は無い。途中の判断は既定で進み、承認時に「仮定」として一覧で見せる

1. `/mule-start` が平文で読み上げる動作への「はい」
2. PR のマージ
3. 本番デプロイ (Sandbox は authorizations.yaml + 明示の指示があれば `/mule-deploy` が置いて疎通確認まで行う)
4. `/mule-learn` の昇格 PR のマージ

## コスト制御

| 仕組み | 何をするか |
|---|---|
| `budget.yaml` | 実行エージェント起動回数と経過時間の上限。**超えたら次を配らない** |
| `--parallel` の自動抑制 | 残予算 25% 未満で強制的に 1 に落とす |
| モデル階層 | 実装は `sonnet` 固定、3 回目の挑戦だけ `opus` |
| `scripts/cost-report.sh` | セッションのモデル別実コスト (USD) |
| `scripts/metrics.sh` | ループ 1 周の時間、初回通過率、差し戻し、カバレッジ |

停止の粒度は「次の配布の前」。実行中のエージェントは途中で止められない。

## 必要なツール

| ツール | 無いとどうなるか |
|---|---|
| Maven + Mule Maven Plugin | 段 2, 3 の検証が動かない (必須) |
| Anypoint CLI v4 + `@salesforce/anypoint-cli-dx-mule-plugin` | `/mule-init` がプロジェクト骨格を作れない。手書き pom はライブラリ取得に失敗する |
| `dw` CLI | DataWeave の秒単位検証が段 2 に落ちる |
| `xmllint` | Mule XML の即時検査が飛ぶ |
| `gh` | PR 作成が手動になる |
| MuleSoft Enterprise の Maven 認証 | MUnit のカバレッジ率計測が動かない (EE 限定機能)。`scripts/coverage-check.sh` が全 flow の到達だけを保証する (flow 内の分岐は見えない) |
