# mule-loop

**MuleSoft API を、チャットではなく「ループ」で作る Claude Code プラグイン。**

[English](README.md) · [日本語](README.ja.md)

`mule-loop` は Claude Code のプラグイン兼プロジェクトテンプレートです。API に何をさせたいかを
伝えると、仕様 → 受け入れ条件 → ゴール台帳 → 実装 → PR まで 1 コンソールで運びます。
**MuleSoft を知らなくても始められます** — `/mule-start` が必要なことを聞いてきます。

実装は一貫して TDD（Red → Green → Refactor）です。設計の考え方は
[docs/methodology.md](docs/methodology.md) にあります。

> **v0.5.5** — [リリースノート](#リリースノート)を参照。

---

## 導入

```bash
# 1. このリポジトリをマーケットプレイスとして登録し、プラグインを入れる
claude plugin marketplace add tmiya4ta/mulesoft-loop-engineering
claude plugin install mule-loop@mule-loop-marketplace

# 2. 依存を入れる（mattpocock-skills、MuleSoft 公式スキル、MCP の前提確認）
claude
> /mule-setup
```

ローカルのチェックアウトから入れる場合:
`claude plugin marketplace add /path/to/mulesoft-loop-engineering`

登録せずに試すなら:

```bash
claude --plugin-dir /path/to/mulesoft-loop-engineering
```

---

## 使い方

```bash
cd my-order-sapi           # Mule プロジェクト（新規でも既存でも）
claude
> /mule-init               # 骨格 + context/, tasks/, budget.yaml を配置（1 回だけ）
#   → ここで context/requirements/ に資料を置く（URL でもよい）
> /mule-start 注文の状態を返す API
```

あとは質問に答えるだけです。それが操作のすべてです。

### 止める位置を変える

| コマンド | どこまで進むか |
|---|---|
| `/mule-start --spec-only` | 仕様と受け入れ条件を作って承認をとるまで |
| `/mule-start --plan-only` | 台帳 `tasks/T-*.md` を切るまで |
| `/mule-start` | 実装、レビュー、PR 作成まで（マージは**人**） |
| `/mule-run` | 台帳の未完了ゴールだけ回す。中断からの再開はこれ |
| `/mule-run T-003` | 1 件だけ |
| `/mule-run --parallel 1` | 直列に落とす。並列が既定で、`--parallel` は**下げる**旗 |
| `/mule-setup` | 外部スキルと MCP の前提を入れる（初回） |
| `/mule-tdd` | 実行エージェントが従う Red → Green → Refactor の規律。人が手で実装するときも使える |
| `/mule-deploy` | マージ後に Sandbox へ置き、`samples/` で疎通確認、失敗は学習ループへ |
| `/mule-learn` | 2 回以上出た失敗を hook / 規則に昇格させる。`--share` で全員に共有 |
| `/mule-status` | **迷ったらこれ。** 今どこにいて次に何をすればよいかを 1 つだけ示す |

---

## 人が判断するのは 5 か所だけ

それ以外は既定で進み、承認時に「仮定」として一覧で提示されます。

| # | 判断 |
|---|---|
| **0** | 開始時に `/mule-start` が `context/decisions.yaml` の空欄を **1 回にまとめて**聞く。先に書いておけば聞かれない。以降、承認まで質問は無い |
| **1** | `/mule-start` が平文で読み上げる動作への「はい」 |
| **2** | PR のマージ |
| **3** | 本番デプロイ（Sandbox は `authorizations.yaml` と明示の指示があれば `/mule-deploy` が行う） |
| **4** | `/mule-learn` の昇格 PR のマージ |

---

## 始める前に人がやること

1. `context/requirements/` に資料を置く（または URL を `context/sources.yaml` に書く）
   > [!IMPORTANT]
   > **ここが空だと `/mule-start` は始まりません。**
2. `context/environment/` に Mule 版や接続先の資料を置く。分からなければ空でよい（自動で調べ、
   根拠つきで記録します）
3. `budget.yaml` の上限を確認する
4. **Sandbox にデプロイさせたい場合だけ:** `context/deployment/authorizations.yaml` の
   `deploy.sandbox` を `allowed` にし、`context/deployment/sandbox.yaml` に置き場所
   （cloudhub2 / rtf、target）を書く

---

## コスト制御

| 仕組み | 何をするか |
|---|---|
| `budget.yaml` | 実行エージェントの起動回数と経過時間の上限。**超えたら次を配らない** |
| 並列の自動抑制 | 残予算 25% 未満で強制的に 1 に落とす |
| モデル階層 | 実装は `sonnet` 固定、3 回目の挑戦だけ `opus` |
| `scripts/cost-report.sh` | セッションのモデル別実コスト（USD） |
| `scripts/metrics.sh` | ループ 1 周の時間、初回通過率、差し戻し、カバレッジ |

> [!NOTE]
> 停止の粒度は「**次の配布の前**」です。実行中のエージェントを途中で止めることはできません。

---

## 中身

```
.claude-plugin/   plugin.json / marketplace.json
skills/
  mule-setup/     外部依存の導入（scripts/setup-deps.sh）
  mule-init/      テンプレート配置
  mule-tdd/       TDD の規律（実行エージェントが必ず従う）
  mule-deploy/    デプロイのループ（Sandbox に置く → samples で疎通 → 失敗を学習へ）
  mule-learn/     学習ループ（失敗を数えて昇格・共有）
  mule-status/    現在地と次の一手のナビゲーション
  platform-assistant/  MuleSoft 公式メタスキルを同梱（Apache-2.0）
  mule-start/     意図 → 計画 → 実行 を通す入口
  mule-run/       計画・実行ループだけ（再開用）
agents/
  mule-executor.md  ゴール 1 件を done_when が通るまで回す（worktree 隔離）
  mule-reviewer.md  読み取り専用レビュー
hooks/hooks.json  編集のたび: scripts/quick-check.sh（数秒の検証）
                  毎ターン:   scripts/loop-reminder.sh（規律の注入）
                  応答の最後: scripts/stop-guard.sh（3 ブロックで締めていなければ 1 回差し戻す）
knowledge/gotchas.md  共有ナレッジ（実行エージェントが毎回読む）
template/         /mule-init が配るもの:
  context/        前提の置き場所（requirements / environment / deployment）+ sources.yaml
  budget.yaml     コスト上限。/mule-run が配る前に確認
  context/deployment/authorizations.yaml   デプロイと実システム接続の許可（人が書く）
  tasks/          ゴール台帳（done_when + 試行ログ）
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh,
                  munit-coverage-mode.sh, run-log.sh, metrics.sh, cost-report.sh
.mcp.json         MuleSoft DX MCP Server（stdio）+ Platform MCP Server（http）
docs/methodology.md
docs/mulesoft-tools.md
```

規律はプロンプトではなく **hook** に置いてあります。長い会話でも薄れないようにするためです。

---

## MuleSoft 公式ツール

[docs/mulesoft-tools.md](docs/mulesoft-tools.md) に、DX MCP Server（21 ツール）、Platform MCP
Server（68 ツール）、公式スキル群（`mulesoft-dx`）の一覧と、どのループで使うかをまとめてあります。
MCP は `.mcp.json` で有効になります。DX MCP Server には Connected App の環境変数が要ります。

```bash
export ANYPOINT_CLIENT_ID=...
export ANYPOINT_CLIENT_SECRET=...
export ANYPOINT_REGION=PROD_JP
```

---

## 必要なツール

| ツール | 無いとどうなるか |
|---|---|
| Maven + Mule Maven Plugin | 段 2, 3 の検証が動かない — **必須** |
| Anypoint CLI v4 + `@salesforce/anypoint-cli-dx-mule-plugin` | `/mule-init` がプロジェクト骨格を作れない。手書き pom はライブラリ取得に失敗する |
| `dw` CLI | DataWeave の秒単位検証が段 2 に落ちる |
| `xmllint` | Mule XML の即時検査が飛ぶ |
| `gh` | PR 作成が手動になる |
| MuleSoft Enterprise の Maven 認証 | MUnit の**カバレッジ率**計測が動かない（EE 限定機能）。`scripts/coverage-check.sh` が全 flow の到達だけを保証する（flow 内の分岐は見えない） |

---

## リリースノート

<details>
<summary><b>v0.5.5</b> — PR #4 の運用 5 点と、困ったときの調べ方</summary>

初期コミット、K ファイルはゴール id 名、`target/` と worktrees を無視、成功時も `learned` を
`failures.jsonl` に、語彙に `connector-behavior` / `loop-ops` を追加。実行エージェントは困ったら
**gotchas → スキル → マニュアル**の順で調べ、1 回でも詰まったら K に残します。`quick-check` の
`p()` 誤検知を修正。

</details>

<details>
<summary><b>v0.5.4</b> — 要件の雛形を同梱し、データモデルは人と決める</summary>

`context/requirements/_template.md`（要件の雛形）を同梱。データモデルは仮定で作らず、開始時の
一括質問と grilling で必ず決めます（System 層は必須）。

</details>

<details>
<summary><b>v0.5.3</b> — 並列取り込みの衝突処理と、動いていた時間で数える壁時計</summary>

並列の取り込みで衝突したときは 1 件だけを failed にして配り直します。壁時計の上限は
**実行エージェントが動いていた時間**で数えるので、ゲートで人を待つ時間が予算を食いつぶしません。

</details>

<details>
<summary><b>v0.5.2</b> — 既定で並列</summary>

着手できるゴールを**既定で並列に配ります**（`--parallel` は上げる旗ではなく**下げる**旗）。
`mule-run` が止まってよい場所を 4 つに限り、進捗の報告先を対話ではなく台帳にしました。根拠は
実測 — `docs/methodology.md` の「実測: System API 1 本の 9.67 時間」。

</details>

<details>
<summary><b>v0.5.1</b> — PR #2 の実測を手順に反映</summary>

デプロイごとに版を上げる（`bump-version.sh`）、CH2 の公開 URL は API で付ける
（`ch2-public-url.sh`）、ポリシーはゲートウェイの型（`api.gateway`）で手順を分ける、同梱スキルを
先に読む。

</details>

<details>
<summary><b>v0.5.0</b> — 実装の先も同じループで回す</summary>

デプロイとポリシーも台帳のゴール（`stage:`）にして同じループで回します。規律（台帳の外で作業
しない / マニュアルを読まない / 3 ブロックで締める）を `UserPromptSubmit` と `Stop` の hook に
移し、長い会話で薄れないようにしました。

</details>

<details>
<summary><b>v0.4.1</b> — 人に聞く場面を最初の 1 回 + 4 ゲートに固定</summary>

質問を最初の一括と 4 つのゲートに限定しました（`context/decisions.yaml`）。途中の判断は既定で
進み、承認時に仮定として一覧にします。

</details>

<details>
<summary><b>v0.4.0</b> — デプロイのループ</summary>

`/mule-deploy` を追加。マージ後に Sandbox（CloudHub 2.0 / Runtime Fabric）へ置き、`samples/` の
期待値で疎通を確かめ、失敗を学習ループに戻します。前版のタグは `v0.3.2`。

</details>
