# mulesoft-loop-engineering

**MuleSoft API を、チャットではなく「ループ」で作る Claude Code プラグイン。**

[English](README.md) · [日本語](README.ja.md)

このリポジトリは Claude Code プラグイン **`mule-loop`** とそのプロジェクトテンプレートです。
API に何をさせたいかを伝えると、仕様 → 受け入れ条件 → ゴール台帳 → 実装 → PR まで 1 コンソール
で運びます。**MuleSoft を知らなくても始められます** — `/mule-start` が必要なことを聞いてきます。

実装は一貫して TDD（Red → Green → Refactor）です。設計の考え方は
[docs/methodology.md](docs/methodology.md) にあります。

> **v0.6.6** — [リリースノート](#リリースノート)を参照。

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
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh, preflight.sh,
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
<summary><b>v0.6.6</b> — N 体が同じ落ち方をする前に、1 回だけ土台を見る</summary>

土台が壊れているとき（依存が解決しない、Exchange の資格情報が古い、推測した GAV が存在しない、
pom を手で書き換えた）、波の実行エージェントは**全員が独立に同じ原因を踏み**、それぞれ 3 回まで試し
（3 回目は opus に上がる）、しかも進捗エージェントは全員が返ってくるまで何も知りません。
**1 つの原因に N×3 回**燃やすことになります。`mule-run` は波を配る前に `scripts/preflight.sh` を実行し、
落ちたら **1 件も配りません**。どのゴールも `running` にせず、`attempts` も増やさず
（ゴールの失敗ではなく土台の失敗なので）、`failures.jsonl` に `build-config` を 1 行書き、
出力を原文のまま人に渡して止まります。

検査は `mvn -q clean package -DskipTests`。`mule-init` の手順 5b が新規プロジェクトの検証に既に使っている
のと同じコマンドです。**MUnit は意図的に流しません。** ループの途中では失敗したゴールの red なテストが
設計どおり木に残っているので、`mvn test` を使うと毎回 1 件目のゴール失敗で全部止まってしまいます。
その代わり、埋め込みコンテナが起動して初めて出る失敗（4.9.0 の BOM、mule-maven-plugin 4.7.0）は
preflight では捕まりません。そこは `mule-init` 5b と `fix-plugin-version.sh` が初期化時に見ており、
走行中に出るようなら雛形同梱のカナリア MUnit を足すのが次の一手です。

preflight は波を `running` にする**前**に走らせます（順序が逆だと、止まったときに `running` のまま
取り残されたゴールが、取り出し条件 `todo`/`failed` に当たらず二度と配られなくなるため）。

</details>

<details>
<summary><b>v0.6.5</b> — v0.6.4 のバグを、学習ループがなぜ拾えなかったのか</summary>

worktree の不具合は **2 回記録されていたのに昇格されませんでした**。今回は事実ではなく
**その配管**を直します。原因は 4 つでした。

1. 語彙に逃げ道が無く、進捗エージェントが `uncategorized` という値を自作していた (finance-api で 13 件)。
   自作の値は集計上ずっと別のバケツになる。**`other` を正式な語彙に追加**し、この値が付くこと自体が
   「語彙が足りない」信号だと定義した。
2. 手順 1 が `(category, symptom)` の**文字列一致**で数えていた。同じ原因が別の言葉で書かれると
   1 回ずつになる。worktree の件はまさに「ゴールファイルが無い」「依存ゴールの成果が無い」で
   2 回に到達しなかった。**原因で数える**ようにした。
3. **語彙が増えても過去の行を読み直す手順が無かった。** `loop-ops` より前に書かれた行は取り残される。
   件数に関わらず毎回 `other` を分類し直す手順 0 を追加し、語彙を増やしたら過去分を読み直すことを必須にした
   (分類のやり直しであって昇格ではない。昇格は分類後に 2 回ルールで判定する)。
4. 昇格先 3 つ (`quick-check.sh` / `CLAUDE.md` / `mule-reviewer`) が**全てリポジトリ内**で、
   `loop-ops` の行き先が無かった。**プラグイン本体の `skills/` / `hooks/` / `scripts/` への PR** を行き先として明記し、
   `gotchas.md` への追記では手順の欠陥は直らないことを書いた。

語彙表は 1 ファイルにしかありませんが、**この項目を書くのは別のエージェント**なので、
`mule-run` と `mule-deploy` にもフォールバックを直接書きました。書き手に届くのはこの記述です。

</details>

<details>
<summary><b>v0.6.4</b> — 実行エージェントに、自分のゴールファイルが無い worktree を配っていた</summary>

`mule-run` は PR を作る直前に**一度しかコミットしていませんでした**。`isolation: "worktree"` の
worktree は HEAD から作られ、**未コミットの変更を引き継ぎません**。つまり実行エージェントは
**(a) いま渡されたはずの `tasks/T-NNN.md` そのもの**も、**(b) 前の波で依存ゴールが作った成果**
(`pom.xml`、`global.xml`、`knowledge/K-*.md`、config) も無い状態で起動し得ました。
`blocked_by` の意味が反転し、**依存を宣言しているゴールほど壊れる**という状態です。
finance-api では T-011 と T-012 の 2 回踏んでいて、どちらも `failures.jsonl` に uncategorized のまま
昇格されずに残っていました。波の全ゴールを `running` にしてから**配る前にコミットする**ようにしました
(`.gitignore` が `target/` と `.claude/worktrees/` を除外済みなので `git add -A` は安全)。

併せて、利用者の `mulesoft-app-development` スキルのうち未取り込みだった配備まわりの 2 点を昇格:
RTF のアプリに Flex Gateway から届かせるには `type: LoadBalancer` の Service が要り、その EXTERNAL-IP を
API インスタンスの Implementation URI に書くこと。Flex Gateway に curl が通らないときは `localhost` が
`::1` に解決されている場合があり、`curl -4` で通ること。

</details>

<details>
<summary><b>v0.6.3</b> — JDBC ドライバは pom の 2 箇所に要る</summary>

v0.6.2 でドライバの `<dependency>` を足し、これで `Cannot load driver class` が防げると書きましたが、
**足りませんでした**。JDBC ドライバは `mule-plugin` ではない素の jar なので、`mule-maven-plugin` の
`<sharedLibraries>` にも宣言しないと DB コネクタから見えません（`sharedLibrary` 側は version を書かず、
`dependency` 側に書く）。2 つ目を忘れても **MUnit は緑のまま通ります**。`db:*` は mock されドライバが
一度も読まれないためで、配備先で初めて落ちます。finance-api の pom には T-009 の時点から理由つきの
コメント入りで入っていたのに、この知見が `knowledge/` にもプラグインにも上がっておらず、
次のプロジェクトが同じ発見をやり直す状態でした。`pom-fragments.xml` に 2 箇所とも載せ、
`mule-basics.md` の 6 節に `[G]` として明記しました。

</details>

<details>
<summary><b>v0.6.2</b> — HTTP request / DB オペレーション / APIkit ルーティングの写経元</summary>

実行エージェントが DB コネクタの jar を自力で開けて XML の書式を調べていました。`reference/` に
finance-api がたまたま使った `db:update` と `db:select` しか無く、外向き HTTP に至っては 1 つも
無かったためです。`template/reference/patterns/` を追加し、`http-request.xml`（request-config と
認証、uri/query params、`responseTimeout`、`http:response-validator`、`HTTP:*` のエラー型、
`http:request` の MUnit mock）と `db-operations.xml`（`db:insert`/`db:delete`、ベンダ別の接続要素、
`db:pooling-profile`、`foreach` + `db:update` のデッドロックを避けるストリーミング戦略、
オペレーション別の戻り値の形と mock）を置きました。`api-main.xml` には APIkit の flow 名の型を 3 つ追加
（**本文を持つ POST/PUT/PATCH だけ mediaType の節が入り、GET/DELETE には入らない**。ここを間違えると
黙って 404 になる）。

`patterns/` を**別ディレクトリにしたのは意図的**です。`reference/` 直下は通ったビルドから抜いたもので、
その保証がこの骨格の一番の価値だからです。新しい方の出所は利用者の `mulesoft-app-development`
スキル（`[S]`）、`mule-basics.md` の実測事実（`[G][K]`）、コネクタの公開ドキュメント（`[D]`）で、
記憶から書いたものは `【未確認】` と明示し、写す前に `describe-connector` で確かめるよう書いてあります。
`pom-fragments.xml` には、コネクタとは別に要る **JDBC ドライバの依存**を追加（版は書いていません。
「GAV は推測しない」という自分の規則に従い、座標は placeholder のまま）。`mule-executor.md` は
ディレクトリではなく**コネクタごとに 1 ファイル**を指すようにし、jar を開ける前にここを見ると明記しました。

</details>

<details>
<summary><b>v0.6.1</b> — HTTP API 以外の Mule アプリ: batch / MCP サーバー / A2A</summary>

`/mule-init` の最初の質問が system/process/experience の層分けでしたが、これは HTTP API にしか
当てはまりません。先に `kind`（`api` / `batch` / `mcp` / `a2a`）を聞き、層は `kind: api` のときだけ
聞くようにしました。`a2a` を選ぶと Maven/MUnit のプロジェクトを作らずに終了し、`agent-network` と
`deploy-agent-network-v1`/`v2` スキルを案内します（Agent Network は `agentNetwork.yaml` / `.agent`
ファイルで、pom.xml を持つ Mule アプリではないため）。`mule-basics.md` に「10. Batch / MCP / A2A」を
追加（`<mcp:server>` という要素は無い、1 tool = 1 flow、SSE の確認方法、batch の `blockSize` /
`maxConcurrency` はクォートしない、など。すべて `[S]`）。`quick-check.sh` の System 層コネクタ検査は
`kind: api` 限定にし、`kind:` 行が無い既存リポジトリは `api` とみなすので**これまでのリポジトリは
何もしなくてそのまま**動きます。

</details>

<details>
<summary><b>v0.6.0</b> — Mule の基礎知識、写経元の骨格、gotchas の主題別整理</summary>

`knowledge/mule-basics.md` を新設（骨格 / 設定 / フロー / エラー処理 / DataWeave / DB / MUnit /
配備 / 命名の 9 節。1 行 1 事実、出所つき）。`template/reference/` は通った API から名前を一般化して
抜いた骨格で、実行エージェントは書く前にここを読みます。`knowledge/gotchas.md` は時系列から主題別に
並べ替え、重複を統合しました。

</details>

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
