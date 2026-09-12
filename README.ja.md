# mulesoft-loop-engineering

**MuleSoft API を、チャットではなく「ループ」で作る Claude Code プラグイン。**

[English](README.md) · [日本語](README.ja.md)

このリポジトリは Claude Code プラグイン **`mule-loop`** とそのプロジェクトテンプレートです。
API に何をさせたいかを伝えると、仕様 → 受け入れ条件 → ゴール台帳 → 実装 → PR まで 1 コンソール
で運びます。**MuleSoft を知らなくても始められます** — `/mule-start` が必要なことを聞いてきます。

実装は一貫して TDD（Red → Green → Refactor）です。設計の考え方は
[docs/methodology.md](docs/methodology.md) にあります。

> **v0.6.7** — [リリースノート](#リリースノート)を参照。

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
| **3** | 本番デプロイ（Sandbox は `authorizations.yaml` に `allowed` と書いてあれば `/mule-deploy` が聞かずに行う。可否は `deploy-guard.sh` が hook で判定する） |
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
  mule-munit/     MUnit の罠を踏む順に並べたチェックリスト（台帳の最大クラスタ 17/62 件）
  mule-deploy/    デプロイのループ（Sandbox に置く → samples で疎通 → 失敗を学習へ）
  mule-learn/     学習ループ（失敗を数えて昇格・共有）
  mule-status/    現在地と次の一手のナビゲーション (人に向けた報告)
  mule-guide/     迷ったときの手引き。状況ごとに次の 1 手とコピーできるコマンド (エージェント向け)
  mule-policy/    ポリシーを探す / 設定キーを見る / 付ける / 外す。典型的なポリシーの表つき
  platform-assistant/  MuleSoft 公式メタスキルを同梱（Apache-2.0）
  mule-start/     意図 → 計画 → 実行 を通す入口
  mule-run/       計画・実行ループだけ（再開用）
agents/
  mule-executor.md  ゴール 1 件を done_when が通るまで回す（worktree 隔離）
  mule-reviewer.md  読み取り専用レビュー
hooks/hooks.json  デプロイの前: scripts/deploy-guard.sh（authorizations.yaml を読んで allow/deny）
                  書き込みの前: scripts/secret-guard.sh（秘密の値そのものがファイルに入るのを弾く）
                  PR の前:     scripts/promote-guard.sh（索引・fixtures・検査の表が通っていなければ gh pr create を弾く）
                  編集の前:   scripts/wave-guard.sh（波で他ゴールに宣言したファイルを進捗エージェントに触らせない）
                  編集のたび: scripts/quick-check.sh（数秒の検証）
                              └ scripts/mule-xml-shape.sh（XSD で落ちる形。台帳の指紋だけ）
                  毎ターン:   scripts/loop-reminder.sh（規律の注入）
                  応答の最後: scripts/stop-guard.sh（3 ブロックで締めていない、または
                              まだ進められるゴールがある(goal-state.sh)なら 1 回差し戻す）
knowledge/fixtures/  hook が本当に弾くかを確かめる最小の入力（bash scripts/fixtures-check.sh）
knowledge/mule-basics.md  索引。実行エージェントは索引を読み、これから触る主題だけを開く
knowledge/basics/*.md  Mule の基礎知識（主題別 10 ファイル、1 項目 1 事実）
knowledge/gotchas.md  索引（症状から主題を選ぶ）
knowledge/gotchas/*.md  実測した地雷（主題別 9 ファイル、根拠つき）
template/         /mule-init が配るもの:
  context/        前提の置き場所（requirements / environment / deployment）+ sources.yaml
  budget.yaml     コスト上限。/mule-run が配る前に確認
  context/deployment/authorizations.yaml   デプロイと実システム接続の許可（人が書く）
  tasks/          ゴール台帳（done_when + 試行ログ）
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh, preflight.sh,
                  munit-coverage-mode.sh, run-log.sh, metrics.sh, cost-report.sh,
                  schema-index.sh (~/.m2 の jar からコネクタ定義と XSD を抜く),
                  plugin-root.sh (プラグインとスキルの場所をパスに解決する),
                  k-new.sh (K ファイルの名前を機械が決める),
                  teeth-check.sh (テストに牙があるかを機械が測る),
                  spec-check.sh (RAML・サンプル・実装の機械で当てられるずれ),
                  jar-leak-check.sh (配る jar に git が無視しているファイルが入っていないか),
                  goal-state.sh (エージェント側で進められるゴールがあるかを exit で返す),
                  gotcha-lookup.sh (エラーの原文から既知の地雷を引く),
                  deploy-precheck.sh (デプロイ前に人に聞くことを 1 回にまとめる),
                  portal-search.sh (Anypoint の値の項目名から、それを返す Platform API の操作を引く),
                  anypoint-api.sh (Platform API を GET だけで叩く。{org} {env} を埋め、--find で応答から探す),
                  gateway-public-url.sh (Flex Gateway に置いた API の外からの URL),
                  policy.sh (ポリシーを find / config / list / apply / remove。書き込みは authorizations.yaml の許可が要る)
.mcp.json         MuleSoft DX MCP Server（stdio）+ Platform MCP Server（http）
docs/methodology.md  考え方、検証器 4 段、**検査の並び (走る順。20 件の通し番号)**
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
<summary><b>v0.6.42</b> — ポリシーの探し方・設定キー・付け方・外し方をスキルにした (`mule-policy`)</summary>

v0.6.41 でゲートウェイの URL は取れるようになりましたが、**ポリシーそのものは「どの資産を、どの設定で
付けるか」が分からないと 1 行も書けません。** 資産の座標 (groupId / assetId / version) も設定キーも
画面にしか無いと思われていたので、探し方ごと道具にしました。

**`skills/mule-policy/`** (新) — 順番は 6 行だけです。典型的なポリシー 13 種の表 (何をしたいか →
assetId → 主な設定キー → 注意) と、契約が要るもの、自動ポリシー、外し方を含みます。

**`scripts/policy.sh`** (新) — 動詞で分かれています。

| | すること |
|---|---|
| `find <語>` | Exchange から付けられるポリシーを探す (assetId と version)。この組織からは **131 件**見えます |
| `config <assetId>` | そのポリシーの設定キー・必須・選べる値を、資産のスキーマ (`schema.json`) から出す |
| `list <インスタンス>` | 今ついているもの (policyId / 版 / order / 設定) |
| `apply <インスタンス> <assetId> [<版>] --config '<JSON>'` | 付ける。版を省くと最新。**`authorizations.yaml` の `policy.sandbox: allowed` が要る** |
| `remove <インスタンス> <policyId>` | 外す |

`apply` と `remove` は書き込みなので、`deploy-guard.sh` と同じ形で許可を読み、`denied` なら止まって
理由を出します (**自分で書き換えない**)。環境名が Production 系なら許可があっても止まります。
資格情報は `anypoint-api.sh` と同じく環境変数から読むので、Secret がコマンド行に残りません。

**実測して分かった一番大事なこと: 設定キーを間違えても 201 が返ります。** `{"nosuchkey":1}` で
適用でき、一覧にも「適用済み」として並びました。**201 は「守れた」の根拠になりません。**
`gotchas/api-manager.md` に項目として足し (6 → 7 件)、スキルにも「`config` で見てから書く」
「効いたかは `policy-check.sh` の exit 0 で決める」を入れました。

実機 (flexGateway のインスタンス) で確かめたこと: `find` / `config` / `list`、
`apply` → **201** (版の自動解決、実装資産の自動選択 — `client-id-enforcement` を付けると
`client-id-enforcement-flex` が入る)、`remove` → **204** (一覧から消え、元の状態に戻る)、
誤ったキーでも 201、`policy.sandbox: denied` と本番系の環境名で止まること。
付けて外す往復は利用者の Sandbox で 1 回だけ行い、元の状態に戻しました。

</details>

<details>
<summary><b>v0.6.41</b> — Anypoint にある値は API で取る。【未解決】だったゲートウェイの公開 URL を解き、引き方を道具にした</summary>

**v0.6.37 (PR #9) で「Managed Flex Gateway の公開 URL は API から取れない」を【未解決】として取り込み、
v0.6.40 の `mule-guide` にも「人に Runtime Manager の画面で確かめてもらう」と書きました。** inventory3-api の
T-007 はそれに忠実に従い、blocked のまま人に URL を聞き続けました。「分からないことを PR してスキルとして
取り込む」という依頼に対して、**「分からない」をそのまま手順にしていた**ことになります。PR をマージした
のはこのリポジトリ側で、【未解決】の中身を確かめずに通しました。

**実際は API の応答にそのまま載っていました。** Gateway Manager API の `getGatewayById` の
`configuration.ingress.publicUrl`。API インスタンスには upstream とゲートウェイ内の待ち受け
(`proxyUri`) しか無いので、インスタンスをいくら読んでも出てきません。当時試していたのは
API Manager と CloudHub 2.0 (Private Space の `dnsTarget` と固定 IP) だけで、**公式の API 36 本のうち
2 本しか見ていませんでした。** 項目名で全部の仕様を引けば 1 手で 2 本に絞れます。

弱いモデルには長い文書より検索道具が効く (v0.6.40) ので、**Platform API の引き方を道具にしました。**

| 道具 (新) | すること |
|---|---|
| `scripts/portal-search.sh '<項目名>'` | 公式ポータルの全 API 仕様 (36 本) を手元に写し、項目名で引く。**その項目を応答で返す操作**まで `$ref` を辿り、そのまま流せる `anypoint-api.sh` の行と、パスに残る変数 (`{gatewayId}`) をどの一覧操作から取るか (仕様の `x-origin`) を出す。依存は python3 の標準ライブラリだけ |
| `scripts/anypoint-api.sh '<パス>' [--find <項目名>]` | Platform API を **GET だけ**で叩く。`{org}` `{env}` を pom と sandbox.yaml から埋め、Secret は環境変数から読む (Sonnet は毎回 `export ...SECRET=<値> && curl` と書いて会話の記録に残していた)。`--find` で応答の中から項目を探す |
| `scripts/gateway-public-url.sh <インスタンス>` | インスタンス → ゲートウェイ → 公開 URL + proxyUri のパス。港が egress なら「内側からだけ」、self-managed なら「動かしている側が決める」と言い分ける |

**仕様だけには頼れないことも実測で分かりました。** Sonnet が読んだ Private Space の `dnsTarget` と
`inboundStaticIps` は、実際の応答にはあるのに公式の仕様には書かれていません。`portal-search.sh` が
外れたら「一覧か詳細を GET して `--find`」に進むよう案内し、その流れ (一覧 → 詳細 → `--find dns`) で
実際に取れることを確かめました。

実機で確かめたこと (managed のゲートウェイ、Private Space、1.13.4。ホスト名は形に置き換えて記録):

| 叩いたもの | 結果 |
|---|---|
| `gateway-public-url.sh inventory3-api` | `https://ft1-xxxxxx.<dnsTarget>/inventory3-api`。ID でも assetId でも同じ |
| その URL + `/inventory` (認証なし) | 401 `Client ID is not present` = ポリシーが応答している |
| 末尾の `/` 無し / ゲートウェイに無いパス | 404 |
| egress (8082) に置いた API | exit 1「内側 `http://ft1:8082/...` からだけ」。公開 URL で叩くと 404 |
| self-managed のゲートウェイに置いた API | exit 1。`getGatewayById` は 404 `Deployment not found` |
| 同じ assetId のインスタンスが 2 つ | exit 2 で候補の ID を並べる |

**ついでに 2 つ見つかりました。**

1. **`policy-check.sh` は URL が分かっても通らなかった。** 最初の `*.req.json` をそのまま GET していたので、
   inventory3 では `PUT /inventory/{inventoryId}/reserve` が選ばれ、ポリシーが効いていても認証ありで 405 に
   なります。3 つ目の引数で GET するリソースを渡せるようにし、省いたときは GET で変数の無い `*.req.json` を
   選ぶようにしました。404 (経路が無い) / 401 (契約が無い) / 405 (GET できない) で次の手を出し分けます。
2. **inventory3 はゲートウェイを迂回できる状態でした。** ゲートウェイ経由は 401 になるのに、upstream が
   アプリの**公開** URL のままで、そちらを認証なしで叩くと `GET /inventory` が 200。`gotchas/api-manager.md` の
   最初の項目 (Proxy 型ならアプリの公開 URL を消す) の 2 回目です。`gateway-public-url.sh` は upstream に
   外から届くかを見て注意を出します。

**同じことを機械で塞ぎます。** `knowledge-index-check.sh` に 4 つ目の検査を足しました: **【未解決】の項目に
`portal-search.sh` で引いた記録が無ければ通さない。** `/mule-learn --share` は PR の前にこれを流し、
`promote-guard.sh` も hook で流すので、「探していないことを取れないと書いた」項目はもう入りません
(弾くことと、記録があれば通すことを両方確かめた)。

`mule-guide` は 5 に「Anypoint にある値の取り方」を足し、7 の「人に画面を見てもらう」を
`gateway-public-url.sh` に置き換えました。`mule-executor`、`/mule-run` (「API から取れない」を blocked の
理由にしない)、`template/CLAUDE.md`、`gotcha-lookup.sh` の外れたときの案内も同じ順に揃えています。

**資格情報の渡し方も具体的にしました。** Claude Code の Bash は毎回新しいシェルなので、「export してもらう」
では人が何をすればよいか分からず、Sonnet は会話で渡された Secret を毎回コマンド行に書いていました。
`anypoint-api.sh` と `deploy-precheck.sh` は「export してから claude を起動し直す」を頼むよう案内します。
あわせて**テンプレートの `.gitignore` で `.claude/settings.local.json` を外しました。** `!.claude/` で `.claude/` を
追跡対象に戻しているため、「今後聞かない」で許可したコマンドに秘密が入っていると `/mule-run` の `git add -A` で
コミットに載る経路がありました (新規プロジェクトから効きます)。

既存のプロジェクトは `preflight.sh` が新しい 3 本を「(無し)」と名指しして `cp` のコマンドを出します。

</details>

<details>
<summary><b>v0.6.40</b> — Sonnet 向けの手引き (`mule-guide`) と、エラーの原文から既知の地雷を引く道具</summary>

Sonnet で回すと「本当に何も分からない」感じになる、という話を受けて、inventory3-api
(Sonnet で要件資料だけから素通し) の台帳 16 件を読みました。迷い方は 3 つでした。

1. **知識はあるのに、必要な瞬間に見つけられない。** Flex Gateway の制約は `gotchas/api-manager.md` に
   ほぼ全部書いてあったのに、読まずに Web 検索と API の試行錯誤で同じ結論に何度も辿り着いた (PR #9)。
2. **禁止が長い文書に埋もれていると守れない。** `CLAUDE.md` に「リポジトリの外を読まない」と書いて
   あったのに、隣のプロジェクトの `pom.xml` を読んで GAV を写した。
3. **写経元を信じて写す。** 4 件はプラグインの写経元やスクリプトを忠実に使って踏んでいた
   (v0.6.39 で直した)。**「何も分からない」の一部は、プラグインが間違ったことを教えていたから**です。

**弱いモデルには、長い文書より検索道具が効きます。** 索引を読んで主題を選ぶ、はエラーを見ている
最中にはできません。

**`scripts/gotcha-lookup.sh '<エラーの原文の一部>'`** (新) — このプロジェクトの K ファイルと
`context/environment/`、プラグインの gotchas と basics をまとめて引いて、**当たった項目を丸ごと**出します。
当たらなければ次に何を調べるか (もっと短い言葉で / INDEX.md / platform-assistant / マニュアル) と、
**やってはいけないこと** (隣のプロジェクトを読む、推測で書いて試す) を出します。
Sonnet が inventory3 で実際に見たエラーの原文 10 個で引いて、9 個が当たりました。

**そのうち 4 個は inventory3 自身の K ファイルにしか無い**汎用の事実でした。次のプロジェクトでは
見えないので、プラグインの gotchas に昇格させました (空のディレクトリ = 次のプロジェクトの立場から
4 個とも引けることを確認):

| 事実 | 行き先 |
|---|---|
| `munit:payload` に `output application/json` を付けると後段で `Stream Compatible` | `gotchas/munit.md` (14 → 15) |
| `apikit:config` を使うのに `mule-apikit-module` を足し忘れて XSD が解決できない | `gotchas/build.md` (14 → 15) |
| 数値の項目 (`port`) に `SET_...` を置くと MUnit が `NumberFormatException` で起動しない | `gotchas/config.md` (3 → 4) |
| `Number as String` が `.0` を落とす (`{format: '#0.0'}` で直す) | `gotchas/dataweave.md` (3 → 4) |

**`skills/mule-guide/`** (新) — **「状況 → 次の 1 手」の表**です。上から全部読まず、今の状況の節を
1 つ開いて番号どおりにやります。節は 8 つ: エラーが出た / 書き始める前 / pom に依存を足す /
MUnit を書く / 分からない値がある / デプロイする / ポリシーを当てる / 止まる・人に聞く。
それと「やってはいけないこと (と、代わりにやること)」の表。

書き方で気を付けたこと:

- **理由は 1 行まで。** 経緯を書くと、弱いモデルはどこが手順なのか見失います (他のスキルは
  経緯と理由が多く、賢い読み手向けに書いてある)。
- **コマンドはそのままコピーできる形。** プレースホルダは `<...>` だけ。
- **実行エージェントは Skill ツールを持たず SKILL.md を生のファイルで読む**ので、
  `${CLAUDE_PLUGIN_ROOT}` を使わず、すべてプロジェクト直下のコマンドで書いた。
- **書いたコマンドとパスを全部当てた**: スクリプト 16 本、パス 11 件がすべて実在。
  v0.6.34 から書いていた `anypoint-cli-v4 account business-group list` と、gotchas に書いた
  `dx mule describe-connector` を**初めて実際に確かめた** (どちらも実在)。

**入口を 1 行で渡します。** 長い規則はプロンプトの中で埋もれるので、`mule-executor` の冒頭、
`template/CLAUDE.md`、`/mule-run` が配るときのプロンプトの 3 か所に「迷ったら `mule-guide`、
エラーが出たら Web 検索の前に `gotcha-lookup.sh`」を 1 行で置きました。

</details>

<details>
<summary><b>v0.6.33</b> — 除外リストの分類を 3 件間違えていた。判断の基準を書いて閉じる</summary>

**hook の発火確認は、このセッションの派生では原理的にできません。** cache が 0.6.32 に上がり
実体と一致した状態でも、索引を壊して `echo gh pr create` を流しても deny は返りませんでした。
**hook 設定はセッション開始時に読まれ、文脈の再読み込みでは差し替わらない**ということです。
追うのをやめ、`knowledge/gotchas/build.md` の記述 (「発火させて確かめる手は無い」) をもって閉じます。

**`checks-audit.sh` の除外リストを見直したら、私の分類が 3 件間違っていました。**

| | 誤り | 実体 |
|---|---|---|
| `done.sh` | 「検査でない」に入れていた | **検査です。** `done_when` を実行して終了コードをそのまま返す = 表の 11 行目。除外していたので、表に載っていなくても気付けませんでした |
| `checks-audit.sh` | 除外リストに入れていた | **表に載っているので冗長。** 載っているものは先に抜けます。両方に書くと「検査ではない」と読めます |
| `mule-xml-shape.sh` | 同上 | 同上 (表の 6b) |

表の 11 行目は `done_when` とだけ書いていて、**それを回す実体 (`done.sh`) を名指ししていません**
でした。名指しするようにしました。表の件数は 21 → 22 になりました。

**手で分類する限り取りこぼします。** だから**判断の基準**をリストの冒頭に書きました:

> **exit コードで合否を答えるか。** 答えるなら検査で、表に載せる。

この基準で残った 12 件は、パスを出す / 名前を出す / 生成する / pom を直す / 記録する / 指標を出す /
注入する / 入れる — **どれも合否を答えません**。`plugin-root.sh` は見つからなければ exit 1 ですが、
それは「無い」を伝えるだけで合否ではないので除外側です。

**これで台帳 58 件と、今日の作業で出た派生も含めて未対応はゼロです。** 3 つの検査
(索引 / fixtures / 表) がすべて exit 0 で、`gh pr create` はそれが崩れたら hook が deny します。

</details>

<details>
<summary><b>v0.6.32</b> — hook が発火しないことを実測。表を突き合わせたら 1 行間違っていた</summary>

**1. 「入れた hook はその日は効かない」を実測しました。**

セッションを開き直すことは私からはできませんが、**発火しないこと自体は確かめられます。**
`echo gh pr create` は `promote-guard` の照合に当たるのに**副作用がありません**。索引をわざと
壊して流したところ、**deny は返りませんでした**。v0.6.8 から存在する `deploy-guard` も、
`deploy.sandbox: denied` のプロジェクトを指して流しても deny を返しません。
**2 つの独立した hook がどちらも発火しない** = このセッションで有効な hook 設定は
セッション開始時に読まれたもので固定されている、ということです。

**そして自分の記述の誤りが 1 つ出ました。** v0.6.16 と v0.6.31 に「cache は**セッション開始時に
だけ**作られる」と書きましたが、`0.6.25` の cache は 22:09、`0.6.29` は 22:26 — **どちらも会話の
途中**でした。**作られる契機は外から見えません。** 観測できたのは 2 つだけです:
「push した瞬間には無い」と「**ディレクトリが増えても、有効な hook 設定は変わらない**」。
断定を取り消して、観測できたことだけに書き直しました。

**2. 並びの表 20 行を実体と突き合わせたら、1 行が間違っていました。**

表は「手順書に散っている検査を 1 本に並べる」ために v0.6.28 で書いたもので、**書いた本人の主張の
まま**でした。全行について「スクリプトが実在するか」「そこから呼ばれているか」を機械で当てたら、
19 行は一致し、**`policy-check.sh` の 1 行だけ呼ばれる場所が違いました。**

| | 表の記述 (誤) | 実体 |
|---|---|---|
| 18 | ポリシー適用後 (`/mule-deploy` の手順) | **`stage: policy` ゴールの `done_when`** (実行エージェントが回す。`/mule-deploy` の手順には無い) |

**表を見て探した人は見つけられません。** 索引と同じで、**ずれた表は無い表より悪い** —
書いてあるので確かめずに従います。17 行目も `/mule-deploy` の手順 5 **と** `stage: deploy` ゴールの
`done_when` の両方であることを明記しました。

**3. だから表も機械が持つようにしました。** `scripts/checks-audit.sh` (新) が 3 つを見ます:

1. 表に出てくるスクリプトが**実在するか**
2. それが**どこかから呼ばれているか** (載っているのに誰も呼ばないものは、走らない検査)
3. **実在する検査が表に載っているか** — 増やしたのに足し忘れると、「どれが自動でどれが手順書任せか」
   の一覧が嘘になります

**書いた直後に 3 が 1 件見つけました** (`setup-deps.sh`。中身を見たら `/mule-setup` が外部スキルを
入れるもので検査ではなかったので、除外リストに分類)。牙の確認 3 通り: 表から 1 行消す →
`jar-leak-check.sh が表に載っていない` / 実在しないスクリプトを表に書く → `実体が無い` / 戻す → 通る。

`promote-guard.sh` に足したので、**表がずれたままでは `gh pr create` が deny されます**
(表自身が 21 行目として表に載っています)。`/mule-learn --share` の手順にも入れました。

</details>

<details>
<summary><b>v0.6.31</b> — 入れた hook はその日は効いていない。hook とナレッジが別の版から来る</summary>

`preflight.sh` を 2 プロジェクトで通しで走らせました。**7 秒、exit 0、誤検知なし** (git、直下 RAML、
`scripts/` の照合、`mvn clean package` の 4 つとも)。jar の mtime で **mvn が実際に走った**ことも
確かめました (飛ばして「ok」と言っていないこと)。

そのあとプラグイン自身の `scripts/` (hook 5 本 + 検査 3 本) に同じ「ずれ」問題があるかを見たら、
**別の、もっと厄介なずれ**が出ました。

**hook はセッション開始時の cache から読まれ、そこで固定されます。**

```
cache の最新: 0.6.29    ← 今のセッションの hook はここから
実体 (clone): 0.6.30    ← plugin-root.sh が返す。ナレッジとスキルはここから
```

`hooks/hooks.json` の `${CLAUDE_PLUGIN_ROOT}` はハーネスが**セッション開始時に**版つきの cache へ
解決します。**あとで実体を直しても、走っているセッションの hook は変わりません。**
cache に `0.6.8 → 0.6.25 → 0.6.29` とセッション開始のたびにディレクトリが増えているのが観測できます。

**つまり今日追加した `secret-guard.sh` と `promote-guard.sh` は、今日このセッションでは
一度も発火していません。** `stop-guard.sh` の `goal-state.sh` 呼び出しも同じです。

**だから今日の検証はすべて「スクリプトに hook の JSON を直接流す」形で行いました。**

```bash
printf '{"tool_input":{"file_path":"/tmp/x.md","content":"..."}}' | bash scripts/secret-guard.sh
```

**これが正しい検証方法です** (発火を待っても永久に来ない)。ただし**書いておかないと、次の人が
「hook で守られている」と誤解します。** だから 3 か所に書きました:

- `knowledge/gotchas/build.md` (12 → 13 件) に症状・原因・検証方法として
- `/mule-learn` の手順 4 に「その hook は今のセッションでは効きません」と検証コマンドを
- 並びの表の hook の注記に

**ナレッジ側は別経路です。** `plugin-root.sh` は版が最大のものを選ぶので (v0.6.16)、
**同じセッションで hook と gotchas が別の版から来ます。** 波は `wave-guard` / `secret-guard` /
`deploy-guard` に頼るので、`preflight.sh` が版のずれを言うようにしました:

```
preflight: hook が古い可能性があります (cache の最新 0.6.29 / 実体 0.6.30)。
           hook (wave-guard, secret-guard, deploy-guard, stop-guard) は cache から読まれ、
           セッション開始時に固定されます。**実体側で直した hook は次のセッションから効きます。**
           この波でその hook に頼るなら、セッションを開き直してください。
```

**「古い」と断定しません。** どの cache をハーネスが選んだかはシェルからは読めないので
(`CLAUDE_PLUGIN_ROOT` は env に無い。v0.6.10 で実測)、「可能性がある」と書きます。

同じ理由で、v0.6.30 で入れた `scripts/` の照合の文言も **「古い」→「差分あり」** に直しました。
実測でまさにその誤りが出ました — push 前のものを手で配ったので、プロジェクト側が**新しい**のに
「古い」と言いました。**どちらが新しいかはそのスクリプトには分かりません。**

</details>

<details>
<summary><b>v0.6.30</b> — 配り切れているかを人が照合するのをやめる</summary>

今日入れたスクリプトが 2 つの既存プロジェクトに配り切れているか照合したら、
**`bump-version.sh` と `ch2-public-url.sh` が両方で古いまま**でした
(v0.6.15 で gotchas の参照先を主題別のパスに直した分)。今回は差分がコメントだけでしたが、
**気付いたのは手で照合したから**です。

`/mule-init` は `template/` を**列挙せず丸ごと**コピーするので、新規プロジェクトは
プラグインに検査が増えても自動で揃います。**既存のプロジェクトはそうなりません。**
検査が 1 本欠けていても、**それを呼ぶ手順が落ちるまで誰も気付きません。**

`preflight.sh` が波の前に照合して、無いもの・古いものを**名指しで**言うようにしました。

```
preflight: scripts/ がプラグインより古いものがあります: teeth-check.sh(無し) goal-state.sh(古い)
           直す: cp <プラグイン>/template/scripts/*.sh scripts/ && chmod +x scripts/*.sh
           (波は止めません。検査が欠けたままだと、その検査が受け持つ失敗を取り逃します)
```

**波は止めません。** 1 行の `cp` で直る話で、止めると全作業が塞がります。止める必要があるものは、
その検査自身が止めます (欠けている検査は呼ばれた時点で落ちる)。**この判断も表に書きました** —
v0.6.29 で「位置が後ろだと防げない」を学んだので、**何を止めて何を止めないかを一覧で見える**
ようにしています。

3 通り実測: 全部揃っている → 無言 / 1 本消す → `teeth-check.sh(無し)` / 1 本古くする →
`goal-state.sh(古い)`。照合先は `plugin-root.sh` が版で選んだプラグインなので、
**版を上げた直後のセッションでも正しい方と比べます** (v0.6.16)。

2 プロジェクトは 22 本すべて同期済みにしました (`finance-api` の `contract-check.sh` は
そのプロジェクト固有のものなので対象外)。

</details>

<details>
<summary><b>v0.6.29</b> — 「呼び忘れても気付けない」検査を hook に寄せる。1 つは位置が後ろで何も防いでいなかった</summary>

v0.6.28 で検査 20 件を走る順に並べたら、**hook は 3 つだけで残り 17 件は手順書が呼ぶ**ことが
一覧で見えました。手順書が呼ぶものは**呼び忘れても誰も気付きません**。忘れたときに何が起きるかで
仕分けて、3 つを hook に寄せました。

**まず、並べたことで自分の誤りが 1 つ見えました。** v0.6.27 で入れた `jar-leak-check.sh` を
**publish のあと**に書いていました。`.gitignore` を見ない jar が Exchange に上がった後に検査しても、
**取り返せません** (その時点で組織の全員から見えます)。

```
v0.6.27:  mvn clean deploy → mvn deploy -DmuleDeploy → jar-leak-check   ← 手遅れ
v0.6.29:  mvn clean package → jar-leak-check → mvn deploy → mvn deploy -DmuleDeploy
```

**検査があっても、位置が後ろなら何も防ぎません。** だから並びの表には「いつ」を必ず書くことにし、
16 の行は「`mvn clean package` の後、`mvn deploy` の前」と位置で書きました。

**hook に寄せた 3 つ:**

**14 → `stop-guard.sh` が `goal-state.sh` を呼ぶ。** 「進められるゴールがあるか」は機械が判定できる
のに、手順書が呼ぶ検査でした。**止まる直前は hook が効く唯一の場所**なので、そこで見ます。
exit 1 (進められる) のときだけ差し戻し、**exit 2 (人の判断待ち) と exit 0 (完了) は通します** —
待つのが正しい動作を邪魔しないためです。3 通り実測: todo あり → 差し戻す / 全部 passed → 通す /
`status: blocked` → 通す。

**7b → `promote-guard.sh` (新)。** プラグイン本体で `gh pr create` を打つ前に
`knowledge-index-check.sh` と `fixtures-check.sh` を通します。忘れたときに起きることが厄介です:
索引がずれると読む側は「合う行が無い」と判断してそのファイルを開かず、**書いた項目が誰にも
読まれません** (v0.6.15 は 19 個ずらし、PR #2 は件数を 11 のまま残しました)。hook の牙が無いと
弾いているつもりで素通りします。**どちらもマージ後に効いてくる**ので、PR を開く前が最後の関所です。
4 通り実測: 通っている → 素通り / 索引をずらす → deny (理由に原文) / `gh pr create` 以外 → 見ない /
**利用者のプロジェクト (検査スクリプトが無い) → 何もしない**。

**7 → `deploy-guard.sh` が jar の混入も見る。** 手順書の 16 を呼び忘れても、
`target/` に jar があって漏れていれば deploy コマンドを deny します。jar が無ければ何も言いません
(これから作るので)。2 通り実測: 混入あり → deny (どのファイルかを名指し) / 消して作り直す → allow。

**寄せなかったもの**も書いておきます。`Agent` ツールの PreToolUse で `preflight` / `budget-check` を
強制する案は**採りませんでした**。`Agent` は実行エージェント以外にも使われるので、
**関係ない呼び出しを止める誤検知の方が高くつきます。** 8〜12 (ゴール 1 件の中の検査) も、
ツールの境界が無いので hook にできません。そこは手順書と `mule-tdd` の証拠ブロックが受け持ちます。

`mule-status` の「次の一手を決める表」も `goal-state.sh` の exit で引くようにしました
(状態を目で数えると、`blocked` が 2 つの意味を兼ねているので必ず取り違えます)。

</details>

<details>
<summary><b>v0.6.28</b> — 「止まってよいか」を機械が答える。検査 20 件を走る順に並べ直す</summary>

台帳で最後に残っていた 1 件は `/goal` の件でした。「ぜんぶ pass」のような条件を置くと、
残りのゴールが**人の許可待ちで正当に止まっている**ときも「まだ終わっていない」と読まれ、
同じ報告を繰り返しても再発火し続けた、というものです。

原因は `/goal` 側だけではありませんでした。**`blocked` が 2 つの意味を兼ねていて、しかもそれが
機械可読でなかった**ことです:

1. `attempts` が 3 に達して諦めた
2. `authorizations.yaml` が `denied` で段に入れない

どちらも「人が動かないと 1 歩も進まない」で、**エージェントの努力では変わりません。** さらに
`blocked_by` が未完了なだけのゴールは「待ち」であって打ち止めではないので、状態を目で数えると
必ず取り違えます。

**`template/scripts/goal-state.sh`** が台帳と `authorizations.yaml` から判定して exit で返します:

| exit | 意味 | `/mule-run` は |
|---|---|---|
| 0 | 全ゴールが passed | 完了を報告する |
| 1 | **進められるゴールがある** | **止まる理由を説明できないなら続ける** |
| 2 | 進められるゴールが 1 つも無く未完了 | **人の判断待ち。止まるのが正しい** |

「進められる」の定義は `status` が `todo`、または `failed` かつ `attempts < 3`。かつ `blocked_by` が
全て `passed`。かつ段の許可がある (`stage: deploy` なら `deploy.sandbox: allowed`)。

**`/goal` の条件は「ぜんぶ pass」ではなく「`goal-state.sh` が exit 0 か exit 2」と書きます。**
そう書けば「完了」と「エージェント側は打ち止め」の両方で条件が満たされます。
`/mule-run` の禁止にも **「exit 2 のときに進めるために `authorizations.yaml` を書き換えること」** を
足しました。それは人の判断で、待つのが正しい動作です。

牙の確認は 6 通り。両プロジェクトが完了済みで exit 0 しか出ず、**1 つの値しか返さない検査は壊れて
いるのと区別できない**ので、台帳を作って全部の枝を通しました:
todo あり → 1 / deploy 段で許可 denied → 2 / **許可を allowed にすると 1 に変わる** /
`attempts` 3 → 2 / `status: blocked` → 2 / 全部 passed → 0。

**そして検査を走る順に並べ直しました** (`docs/methodology.md` の「検査の並び (走る順)」)。

既存の「検証器は 4 段」は**コードに対する検証器を速さで分けた**表で、実際に 1 周で走る検査は
それ以外にもあり、手順書の中に散っていました。20 件を通し番号で 1 本にして、
**いつ走るか / 通らないと何をしないか / exit の契約**を並べました。抜粋:

```
 2 波を配る前   budget-check.sh    → 1 件も配らない
 3 波を配る前   preflight.sh       → 1 件も配らない
 4 書き込み前   secret-guard.sh    → その書き込みを deny (hook)
10 ゴールの中   teeth-check.sh     → 牙が無いテストを残さない
14 止まる前     goal-state.sh      → 止まってよいかを答える
16 配る前       jar-leak-check.sh  → 置かない
17 置いたあと   smoke-check.sh     → 完了にしない
20 昇格の前     fixtures-check.sh  → 昇格したと言わない
```

**hook は 3 つ (4, 5, 7) で、エージェントが忘れても走ります。** それ以外は手順書が呼ぶので、
呼び忘れは起こりえます。**だからこの表があります** — どれが自動でどれが人 (エージェント) 任せかが
一覧で分かるようにするためです。`/mule-run` には表への参照だけを置き、
**両方に同じ内容を書かない**ようにしました (索引と実体がずれる話と同じ理由です)。

</details>

<details>
<summary><b>v0.6.27</b> — 最後の 9 件。既に記録済み 6 件、プラグインの手順の誤り 1 件、新しい hook 2 つ</summary>

`dataweave-null` 2 + `secret-leak` 2 + `deploy-*` 5 = 9 件。**6 件は既に行き先に入っていました:**

| 台帳の件 | どこにあったか |
|---|---|
| `payload as String` が `Cannot coerce` (×2) | `gotchas/apikit-http.md` + `basics/dataweave.md` |
| `oracle.jdbc.OracleDriver` が `Cannot load class` | `basics/db.md` の「JDBC ドライバは pom の**2 箇所**に要る」。pom を見たら実際に `<sharedLibraries>` で解決していた |
| ORA-12505 / ORA-00942 / 別サービス経由 (×3) | inventory2-api の `context/environment/resolved.md`。接続文字列と実測日つきで入っていた |

**行き先の表が機能している**ということです。`environment-fact` を `context/environment/` に送る規則
(v0.6.12) が無ければ、Oracle の SID / Service Name の話が全プロジェクト向けの gotchas に入って
**他のプロジェクトで嘘になっていました。**

**残る 3 件のうち 1 件は、このプラグインの手順が間違っていた件です。**

`mule-deploy` は `mvn clean deploy -DmuleDeploy` を **1 コマンド**で書いていました。手順どおりにやると
`Failed to retrieve artifact information from Exchange. Reason: 404 There is no asset matching given
parameters.` で**必ず**落ちます。`muleDeploy` がまだ publish されていないアセットを先に参照するためです。

- 手順を 2 段階にしました: `mvn clean deploy` (publish のみ) → `mvn deploy -DmuleDeploy` (配置)。
  2 段目に `clean` を付けると成果物が消えてやり直しになる旨も書きました。
- 同じ 404 は `<businessGroupId>` 欠けでも出ます (認証トークンの**既定組織 = Root** を見る)。
  `deploy-config.sh` が pom の `groupId` から入れるようにしました。
- `gotchas/deploy.md` (6 → 7 件) に症状と原因を記録しました。

**新しい hook / 検査 2 つ。どちらも「値やパターンを推測しない」形にしました。**

**`jar-leak-check.sh`** — `-DattachMuleSources` は **プロジェクト全体をファイルシステムから丸ごと**
`META-INF/mule-src/` に入れ、**`.gitignore` を見ません**。実測では `.gitignore` 済みで DB パスワードを
平文で持つファイルがそのまま jar に入りました。git には一度も入っていないので `git log -S` では
見つからず、jar は Exchange に上がって組織の全員から見えます。**気付くのは配る側だけです。**
判定は「**git が無視しているファイルが jar に入っているか**」— 名前のパターンで秘密を当てるより
誤検知が少なく、`credential` という名前でなくても引っかかります。`mule-deploy` の手順 3b に入れました。

作る途中で 2 つ自分で踏みました。どちらも**この検査自体が黙って ok を返す**形でした:

- `git rev-parse --show-toplevel` に `cd` していたので、monorepo (inventory2-api の git 直下は
  `mule-demos`) で `target/*.jar` を見つけられず「jar がありません」。→ `cd` を外した
- `git check-ignore --stdin` は**空行が 1 つあると `fatal: empty string is not a valid pathspec` で
  exit 128** になり、`|| true` がそれを飲んで「混入なし」と嘘をついた。→ 空行を落とし、
  **exit が 0/1 以外なら「判定できなかった」と言って止める**ようにした

**`secret-guard.sh`** (PreToolUse Edit|Write) — 資格情報を進捗メモとして**追跡ファイル 3 つに
書き込みかけた**実例があり、台帳の対策は「コミット前に grep する運用を徹底する」でした。
それは規則で、破った側が自分で守る話になります。だから機械で弾きます。

**パターンで秘密を当てません。値そのものを照合します。** 照合元は秘密が正しく置かれている場所
(環境変数 `ANYPOINT_CLIENT_SECRET` / `ANYPOINT_CLIENT_ID`、`~/.m2/settings.xml` の `<password>`) で、
8 文字未満は使いません。だから変数名や書式に依存せず (base64 でも UUID でも当たる)、
秘密でない文字列を弾きません。**`${env.X}` の参照は弾きません。**

**値は絶対に出力しません。** hook の出力は会話に入るので、そこに値を書いたら弾く意味がありません。
`fixtures-check.sh` に**「deny の理由に値が出ていないこと」自体の検査**を入れました。

牙の確認 (`bash scripts/fixtures-check.sh`、8 件全部): 値をそのまま書く → deny /
deny の理由に値が出ていない / 値を含まない書き込み → 素通り / `${env.X}` → 素通り。
jar は 3 通り (混入あり → exit 2 / 消して作り直す → exit 0 / `attachMuleSources` 無し → 対象外)。

</details>

<details>
<summary><b>v0.6.26</b> — 写経元に未検証の記述が 1 つあった。実測したら反証された</summary>

`munit-coverage` 8 件 + `munit-mock-missing` 4 件は **12 件すべてプラグイン側は対処済み**
(`gotchas/munit.md`、`mule-munit`、`router-test.xml`、`teeth-check.sh`)。残っていたのは
inventory2-api の**牙の弱い振り分け flow のテスト**という実作業でした。

**まず牙が無いことを機械で示しました** (推論ではなく実測。`teeth-check.sh` の初仕事の 1 つ):
モックの戻りを `#[[]]` → `#[[{}, {}]]` に変えても `Tests run: 1 - Failed: 0`。
`vars.httpStatus` が notNullValue かどうかしか見ていないので、当然素通りします。

4 本を `router-test.xml` の型付け方式に置き換え、**応答の中身を samples と比較する**形にしました。
behavior のモックは承認済みテストから**機械で写しました** (手で写すとずれるため)。
4 本とも牙を実測 (モックの戻りを壊す / 期待値の参照先を別サンプルにする → 狙った case が `Failed: 1`)。
全 15 スイート緑、`flow coverage: 12/12 (100%)` を維持。

**ここで写経元の誤りが出ました。** `template/reference/router-test.xml` にはこう書いてありました:

> **main flow を叩く** (listener + apikit:router。本物の APIkit 検証を通したいとき):
> APIkit が経路とスキーマを判定するので `method` / `listenerPath` / `relativePath` /
> `requestPath` と、`headers` の `content-type` が効く。

**未検証でした。実測すると成り立ちません:**

- 型付け attributes を渡して `flow-ref` しても `APIKIT:NOT_IMPLEMENTED`
- APIkit が経路判定に使う `maskedRequestPath` は **DataWeave から渡せない** —
  `Unable to found builder method: maskedRequestPath() on class HttpRequestAttributesBuilder`。
  mule-http-connector 1.10.6 で**フィールド自体は存在する**のに builder に無いので、渡す手段がありません
- `listenerPath: "/*"` + `requestPath: "/inventory/1"` に変えても `NOT_IMPLEMENTED` のまま

v0.6.23 で直した「1 接続先の実測を全接続先の事実として書いた」件と**同じ種類**です。あちらは
根拠が 1 件、こちらは根拠がゼロでした。**書いた側は区別できません。読む側は確かめずに従います。**

- `router-test.xml`: 当該記述を実測の結果に差し替え、**未検証だったことも書きました**
- `gotchas/munit.md` (13 → 14 件) と `mule-munit`: 「main flow は `flow-ref` で振り分けられない」を追加
- inventory2-api の `api-main-test.xml` は**牙を付けられないと分かった**ので、理由を書いて据え置き。
  **「型付けすれば検証できる」と思って作り直さないでください**と明記しました。
  APIkit の経路判定は段 4 (`smoke-check.sh`、v0.6.25 で初めて機能するようになった) が受け持ちます。

</details>

<details>
<summary><b>v0.6.25</b> — 配備後の疎通確認が一度も成立していなかった (同じプラグインの中で形が食い違っていた)</summary>

`loop-ops` 10 件を当たったら、**8 件は既に機械化・対処済み**でした:

| 台帳の件 | 何が受け持っているか |
|---|---|
| worktree に初期コミットが要る | `/mule-run` 手順 4 |
| K ファイルの番号衝突 | `k-new.sh` (v0.6.13) |
| worktree の基点がゴールより古い (×2) | v0.6.7 の実測 + isolation の判定表 |
| 進捗エージェントが自分の分担宣言を破る | `wave-guard.sh` (v0.6.14) |
| worktree の相対パスが別プロジェクトに解決 | 絶対パス + ゴールの中身をプロンプトに貼る (v0.6.7) |
| worktree の基点がセッション固定 | 判定表で isolation を使わない側に落とす (製品バグとして報告済み) |
| `/goal` が blocked を「未達」と読む | **未解決。** `/goal` 側の機構が要る |
| `smoke-check.sh` がサンプルの形を知らない | **これを直しました** |

**残っていた 1 件は、プラグイン自身の中の食い違いでした。** 受け入れ条件のサンプルは MUnit の入力の形

```
in.json  {"inventoryId": 3, "body": {"quantity": 5.0}}
out.json {"status": 200, "body": { ...応答ボディ... }}
```

なのに、`smoke-check.sh` は**ファイル全体を HTTP のボディとして送り**、**応答を out.json 全体と
比べて**いました。つまり:

- 送っていたボディが `{"inventoryId":3,"body":{...}}` (`.body` だけを送るべき)
- 期待値が `{"status":...,"body":...}` (応答ボディと一致するはずがない)
- **status を一度も比べていなかった** (out.json は持っているのに)
- 既定のパスが `POST /<resource>` で、実際は `PUT /inventory/{inventoryId}/reserve`

**つまり配備後の疎通確認は、当たったことが一度も無かった** ということです。`docs/methodology.md` の
段 4 (配備先への契約検査) は、MUnit が原理的に見られないもの (SQL、型、二重包み) を捕まえる**最後の砦**
として置いてあります。そこが空振りしていました。台帳には inventory2-api の 1 件として載っていましたが、
**実測すると finance-api も同じ形**で、両方壊れていました。

直したもの:

- **ボディ**: `in.json` に `body` があればその中身だけを送る (無ければ全体。後方互換)
- **期待値**: `out.json` に `status` と `body` があれば**両方を別々に**比べる。status 違いは
  `status(409≠200)` の形で出す
- **method / path を RAML から導く**。`api/*.raml` の method と path を列挙し、(1) path の末尾が
  case 名の先頭トークンと一致、(2) path が resource 名を含む、(3) **path の `{...}` と in.json の
  トップレベルのキーが完全一致**、(4) body の有無が method と整合 — で選びます。
  (3) が無いと `get-ok` が集合の `GET /inventory` に解決されました (**個別と集合の取り違え**)。
- **クエリ文字列**: `in.json` の `query` を URL に付ける (検索系のサンプルはこの形)
- **`--dry-run <base>`**: 何を送るつもりかだけを出す。**配備前に確かめられます**

`--dry-run` で 2 プロジェクトの **25 ケース全部**が RAML から正しい method・path・クエリに解決され、
既定に落ちたものは 1 つもありませんでした:

```
inventory/reserve-ok   PUT  https://x/api/inventory/3/reserve  (RAML)
  body:     {"quantity":5.0}
  expected: status 200 / body {"inventoryId":3,...}
inventory/search-ok    GET  https://x/api/inventory?warehouseCode=WH-MAIN&lowStockOnly=true  (RAML)
name/not-found         PUT  https://x/api/customers/CUST99999/name  (RAML)
```

`.req.json` は明示的な上書きとして残しました (`{...}` の置換はそちらでも効きます)。

</details>

<details>
<summary><b>v0.6.24</b> — RAML とサンプルのずれ 2 つを機械で当てる。片方は台帳より 1 件多かった</summary>

`raml-mismatch` 5 件のうち 3 件は既に `gotchas/apikit-http.md` にあり、意味の問題でした
(`requestPath` にベースパスが付く、`error.description` の書式、先行テストが固定した status)。
残る 2 件は**どちらも機械で当てられました**。`template/scripts/spec-check.sh` (新)。

**検査 1: 同じ flow を叩くサンプルの `instance` の形が揃っているか** (exit 2 の対象)

どのサンプルがどの flow のものかは **MUnit が持っています** (`munit:test` の中の `flow-ref` と
`readUrl("classpath://samples/...")`)。**ファイル名からは推測しません** — finance-api は
`not-found.out.json`、inventory2-api は `reserve-not-found.out.json` で命名規則が違い、
名前で当てると片方で機能しません (実際にそう書いて finance 側が全部 1 件のグループになりました)。

台帳には「`reserve-not-found` の `instance` が `/reserve` 無しだった」とあります。実際に走らせたら
**3 つのうち 2 つが崩れていました**:

```
flow reserve-inventory:
  2 段  /inventory/999          (reserve-not-found.out.json)
  2 段  /inventory/1            (reserve-upstream-error.out.json)   ← 台帳に無い
  3 段  /inventory/3/reserve    (reserve-insufficient.out.json)
```

**走らせる場所は「人に承認してもらう前」です** (`/mule-run` の手順 3)。承認後に見つけても、
サンプルは「期待値は変えない」の対象になるので直せるのは実装側だけになります。実例がまさにそれで、
inventory2-api は承認済みサンプルに合わせて実装を「見つかった後にだけ `/reserve` を付け直す」
2 段構成にしていました。**承認前ならサンプルを揃えるのが一番安い。**

**検査 2: RAML の必須項目が実装のどこにも出てこないか** (**警告のみ**)

`ReserveRequest.lastUpdated` が必須なのに実装が一切参照しておらず、`mule-reviewer` が読んで
見つけた件です。同じことを機械で当てられます。**ただし exit 2 にはしません** — 受けた body を
そのまま次の API に渡す通過型では名前が出てこないのが正常で、**機械では正誤を決められない**からです。
`mule-reviewer` の観点 2 の最初に走らせ、出力を鵜呑みにも無視にもせず、実装を読んで判定させます。

**両方の検査に牙があることを実測しました。** 検査 2 は 2 プロジェクトとも無言だったので
(`lastUpdated` は既に直っている)、無言と牙が無いのを区別するために細工しました:
実装に無い必須項目を RAML に足す → `PUT /inventory/{inventoryId}/reserve の ReserveRequest.zzzNeverReferenced`
と出る。`required: false` を付けた項目は**無視される**ことも確認。どちらも RAML を元に戻しました。
検査 1 は finance-api で 4 flow すべて ok (誤検知なし)、inventory2-api で上記を検出。

</details>

<details>
<summary><b>v0.6.23</b> — 共有ナレッジに嘘が 1 行あった (1 接続先の実測を全接続先の事実として書いていた)</summary>

`connector-behavior` 5 件 + `environment-fact` 2 件を当たったら、**7 件のうち 5 件は既に記録済み**で、
`environment-fact` 2 件も行き先どおり `context/environment/cif-schema.md` に入っていました。
残った 2 件が**同じクラスなのに結論が真逆**で、そこで共有ナレッジの誤りが出ました。

`knowledge/gotchas/db.md` と `basics/db.md` にはこう書いてありました:

> TIMESTAMP 列は Mule に入った時点で **DataWeave の String** (`2026-09-05T16:47:13.033`、TZ 無し)。
> `as String` は恒等変換。

**平叙で書いてありますが、根拠は Derby 1 件の実測でした。** Oracle では逆です:

| 接続先 | `db:select` が DataWeave に渡す型 | `as String` |
|---|---|---|
| Derby (clouderby-jdbc) | 既に `String` | 恒等変換で無害 |
| Oracle (`db:generic-connection`) | 素の `Object` | **落ちる** (`Cannot coerce Object to String`) |

inventory2-api は実際にこれで 500 になりました。**しかも MUnit は 15 スイート全部緑でした** —
`mock-when` が返していたのはプレーンな文字列で、型の不一致はモックで消えるからです。
気付いたのは配備して curl を当てたときです。

- `gotchas/db.md` (6 → 7 件): 両方の実測を並べた独立の項目にし、**「1 つの接続先での実測を、
  全接続先の事実として書いてはいけない」**ことを項目の中に明記しました。直し方は
  「dwl で型を当てにせず SQL 側で `TO_CHAR` して文字列で渡す」で、同じ列を読む SELECT を**全部**直す
  (楽観ロックの比較経路も同じ列を読んでいました)。
- `basics/db.md`: 該当行を「DB とドライバで違う」に直しました。**`[K]` から `[G]` に変わりました**
  (2 プロジェクトの実測になったため)。
- `gotchas/munit.md` (12 → 13 件) と `mule-munit` の「MUnit で検証できないもの」に
  **「`mock-when` が返す値の型は実物と違ってよいので、型の不一致は緑のまま通る」**を足しました。
  **対策はモックを実物に似せることではありません** — 実物の型が分からないから間違えるので。
- `gotchas.md` の追記の規則に **「1 つの接続先で測った事実は、接続先の名前を本文に書く」**を足しました。
  範囲が 1 接続先に閉じるなら行き先は `context/environment/` です。

索引の件数は 2 つとも `knowledge-index-check.sh` が **exit 1 で止めて**から直しました
(db 6→7、munit 12→13)。v0.6.17 のゲートが 2 回目も働いています。

</details>

<details>
<summary><b>v0.6.22</b> — `error-handler` 5 件は文章で足りていた。足りなかったのは写経元 1 つ</summary>

`error-handler` 5 件 (finance 4 + inventory2 1) を 1 件ずつ当たった結果、**機械化するものはありませんでした。**

| 台帳の件 | 判定 |
|---|---|
| `try-scope-resume-after-continue` (再開位置) | 意味の問題。機械が判定できない。`gotchas/error-handling.md` にあり |
| `shared-handler-propagate-breaks-others` | 同じ。設計の選択なので弾く対象にならない |
| `builtin-error-type-not-raisable` | ビルドが**大声で**落ちる。直し方は既に文章にある |
| `custom-error-type-undeclared` (**2 プロジェクト**) | 同じく大声で落ちる。**ただし写経元が無かった** |

`custom-error-type-undeclared` を hook で弾くのは**やめました**。TDD では
`on-error-continue type="APP:X"` を書いてから `raise-error` を書くので、**その途中の状態を
deny すると正しい手順を邪魔します。** ビルドは `Could not find error 'APP:X'` と明示的に落ちるので、
黙って通る類ではありません。足りなかったのは「では何を書けばいいか」でした。

**波の中で `global.xml` を先に書くと、実処理 flow を書くゴールはまだ走っていません。**
「あとで本物の `raise-error` を書く」では間に合わず、その時点でビルドが落ちます。
inventory2-api はここで**型登録スタブを独自に作って**解決していました。
v0.6.14 の表では写経元は 1 回で作る対象なので、`template/reference/` に取り込みました:

- `global.xml` に `app-error-types` (`sub-flow`)。`vars.appErrorTypeToRaise` で選んだ型だけ
  `raise-error` し、未指定なら `otherwise` で**何もせず戻る** — だから MUnit から安全に呼べる
  (`coverage-check.sh` は全 flow が MUnit から `flow-ref` されることを要求する)。
  各ゴールが本物を書いたら**消してよい**ことも書きました。
- `error-types-test.xml` (新) がその MUnit。

**ここで元の実装の牙の無さが出ました。** inventory2-api のスタブ用 MUnit は
`expression="#[true]" is="#[equalTo(true)]"` でした。カバレッジは通りますが何も検証していません。
`expectedErrorType` を使えば**同じ手間で「その型が本当に raise できる」= スタブの存在理由そのもの**を
検証できます。写経元はその形にし、`expectedErrorType` は推測ではなく `mule-munit.xsd` で確認しました。

**写経元は実測してから配りました。** inventory2-api で実際に流して `Tests run: 2 - Failed: 0`、
そのうえで v0.6.21 の `teeth-check.sh` で牙を測りました (期待型を別の型に差し替え → 狙った case が
`Failed: 1` / `vars.probe` を存在しない変数に差し替え → no-op 側が `Failed: 1`)。
**新しい写経元の最初の使い道が、自分の牙の測定でした。**

inventory2-api の `#[true]` のテストは、この形に置き換えて `flow coverage: 12/12 (100%)` を保ったまま
牙が付いたことを確認済みです。

</details>

<details>
<summary><b>v0.6.21</b> — 牙の確認を手でやるのをやめる (3 回、確認そのものが当たっていなかった)</summary>

台帳の `test-toothless` 6 件を 1 件ずつ当たったら、内訳が予想と違いました。**5 件が「検査自体が一度も
走っていなかった」**で、そのうち **3 件は「牙の確認そのものが当たっていなかった」**ものでした:

- `tamper-missed-due-to-line-number-drift` — 行番号を決め打ちした `sed` が外れ、**細工が 1 文字も
  当たっていない**まま緑を「牙が無い」と誤読しかけた
- `mutation-test-wrong-failure-path` — 別の前処理が先に落ちて exit 1。**狙った case は一度も走っていない**
- `uncaught-exception-in-check-prelude` — 前処理の例外でスタックトレースだけ出て NG 行ゼロ、exit 1

共通の誤りは 1 つです。**exit が非ゼロになったことを牙の証拠にした。**

v0.6.11 でこれを `mule-munit` に「3 つを実測する」という**文章**で書きました。文章では足りません
— 上の 3 件は全部「気を付ける」で防げるはずのものです。`template/scripts/teeth-check.sh` に移しました:

```bash
bash scripts/teeth-check.sh --file src/test/munit/name-test.xml \
     --old 'samples/name/not-found.out.json' --new 'samples/name/ok.out.json' \
     --case name-not-found
```

見るのは 3 つとも機械です: **細工が当たったか** (当て先が 1 箇所でなければ細工しない。行番号は
使わない) / **細工前は緑か** / **狙った case が失敗として現れたか**。対象ファイルは異常終了でも
元に戻します。

**MUnit の出力の形は推測していません。** finance-api の `name-test.xml` で実測しました:

```
細工前: = Tests run: 7 - Failed: 0 - Errors: 0 - Skipped: 0 ... =
細工後: munit.01 ERROR FAILURE - test: name-not-found - Time elapsed: 0.03 sec
        = Tests run: 7 - Failed: 1 - Errors: 0 - Skipped: 0 ... =
```

だから条件は `FAILURE - test: <case 名>` と `Failed:` が 1 以上の 2 つです。

**牙の確認に牙があることを、実 mvn で 6 通り確かめました** (この検査自体が `test-toothless` に
なるのを避けるため):

| 試したこと | 結果 |
|---|---|
| 当て先が 0 箇所 | exit 2 |
| 当て先が 3 箇所 (`equalTo(vars.expected.status)` は実際に 3 箇所あった) | exit 2 |
| case 名の打ち間違い | exit 2。**`mvn` を回す前に**止まる |
| 期待値の参照先を別の sample に差し替え | **exit 0 (牙あり)**。`Failed: 1` と case 名を確認 |
| `doc:name` だけ壊した (assert が読まない箇所) | exit 2「**牙がありません**」 |
| 別の case を壊して `--case` は元のまま | exit 2「**落ちたのは別の case**」+ 実際に落ちた case 名 |

最後の 2 つが本題です。5 番目は**牙の無いテストを見つける**枝で、6 番目は
**`mutation-test-wrong-failure-path` そのもの**を機械が捕まえた形です。

途中で 1 つ直しました。`Failed: 0` のときに「落ちたのは別の case です」と言っていました
(原因も直し方も違うので、集計を先に見るよう並べ替えた)。細工の表示も `grep` から**差分**に変えました
— 別の case が同じ sample を読んでいて、細工と無関係な 3 行まで並んでいたためです。

`mule-munit` からは「3 つを実測する」という手順を消し、`mule-tdd` の証拠ブロックに `teeth:` の行を
足しました。

</details>

<details>
<summary><b>v0.6.20</b> — スキーマ索引は「除外されると黙って届かなくなる」ので、除外を見つけて言う</summary>

2 プロジェクトの未コミット変更をレビューしていて、`reference/mule-schema/` が両方とも**未追跡**の
ままだったことに気付きました。ここで v0.6.7 の実測が効いてきます: **`isolation: "worktree"` の
worktree は `origin/main` から切られるので、追跡されていないファイルは実行エージェントに一切届きません。**

届かないと何が起きるか。`agents/mule-executor.md` と `mule-munit` は
「**コネクタの要素名、操作名、パラメータ名を推測してはいけません**」と書いて `INDEX.md` を指しています。
索引が無ければ、**禁止だけが残って推測する以外に手が無くなります。** このスクリプトを作った理由が消えます。

今回の 2 件では実際には壊れていませんでした。`/mule-run` は配る前に `git add -A` するので、
`.gitignore` で除外していなければ自動的に入ります (レビューしてコミットしたので今は追跡済み)。
危ないのは**除外されている場合だけ**で、そのときは何も言わずに届きません。

- `scripts/preflight.sh`: 索引が `git check-ignore` に当たるなら、**理由を添えて言う。波は止めない**
  (索引が無くてもエージェントは gotchas → スキルの順に戻れるので、止めるほどではない)。
  位置は `mvn package` の**後ろ**です。ビルドが落ちる波は配られないので、そのときこの警告は要りません。
- `scripts/schema-index.sh` の冒頭に「**生成物を .gitignore に入れないこと**」とその理由を書きました。
  564 KB の生成物なので、除外したくなるのが自然だからです。

検査の 3 つの枝 (除外あり → 警告 / 除外なし → 無言 / 索引がまだ無い → 無言) を実測しました。

</details>

<details>
<summary><b>v0.6.19</b> — `mule-build` スキルは作らない。8 件のうち機械で弾ける 3 件を弾く</summary>

台帳の `build-config` 6 件 + `xml-namespace` 2 件を主題にした `mule-build` スキルを作る予定でした。
**作りませんでした。** 8 件を 1 件ずつ当たったら、**7 件は既に `knowledge/gotchas/` に書いてあり**、
スキルは 3 つ目の写しになるところでした (`gotchas` の原文 → `basics` の要約 → スキル)。
v0.6.15 で読む量を減らしたばかりなので、その一部を返すことになります。

v0.6.14 の表がこれを決めます。**機械で弾けるものは文章にしない。** 8 件を行き先で分けました:

| 台帳の件 | すでにある | 今回やったこと |
|---|---|---|
| `db:sql` を属性で書く | `gotchas/db.md` | **hook で弾く** |
| `<try>` の中の `error-handler` の位置 | `gotchas/error-handling.md` | **hook で弾く** |
| 直下の `api/*.raml` がクラスパスに乗らない | `gotchas/build.md` | **preflight で止める** |
| `dw validate` の `p()` 誤検知 | `gotchas/dataweave.md` | `quick-check` が既に除外済み |
| `.gitignore` に `target/` が無い | — | テンプレートに既に入っている |
| JDK 混在 (`javac` と `java`) | `gotchas/build.md` | 端末の事実なので文章のまま |
| 環境変数がプロパティを上書きしない | `gotchas/config.md` | 同じ |
| ベンダの JDBC jar が fat でない | **無かった** | `gotchas/build.md` に追記 (10 → 11 件) |

**`scripts/mule-xml-shape.sh`** — `xmllint --noout` は形式しか見ないので、XSD で落ちる形は素通りします。
かといって `xmllint --schema` は使えません: **コネクタの XSD は jar に入っていない**からです
(jar が持つのは `*-extension-descriptions.xml` = 説明文で、XSD はランタイムが拡張モデルから生成する)。
実測でも `~/.m2` から抜けた 21 ファイルのうち `.xsd` はランタイム側だけでした。**だから汎用の検証はせず、
台帳に実測がある指紋だけを見ます。** content model は推測せず `mule-core-common.xsd` の原文から写しました:

- `flowType` : `description?, messageSource?, processor+, abstract-error-handler?`
- `tryType` : `processor+, abstract-error-handler?`
- `subFlowType` : `description?, processor+` ← **error-handler を持てない**

**ルート直下の `<error-handler name="global-error-handler">` は位置の制約が無いので見ません。**
`template/reference/global.xml` がまさにこの形で、ここを弾くと写経元が通らなくなります。

牙の確認 (`bash scripts/fixtures-check.sh`): 違反 3 形が exit 2、**正しい形 (ルート直下の error-handler)
が素通り**することを実測。`knowledge/fixtures/` に最小の入力として残しました。deny する hook は
**誤検知が編集を止める**ので、弾く側だけ試すのでは足りません (台帳の `dw-validate-false-positive-p` が実例)。
`/mule-learn` の手順 4 にも「`ok-*.xml` を 1 つ足す」を書きました。

**preflight の RAML 検査は `mvn package` では捕まりません。** package は通り、落ちるのはアプリの初期化時
(`InitialisationException: Raml not found`) です。台帳 T-001 は package が通ったあとにゴールを 1 件
失っています。だから package の**前**に見ます。`src/main/resources/api/` に置く構成は既定でクラスパスに
乗るので、そのときは検査しません。

`gotchas/build.md` への追記では **v0.6.17 の索引ゲートが実際に働きました** —
件数を直す前に `knowledge-index-check.sh` が「10 件だが実体は 11 件」と言って exit 1 になりました。

</details>

<details>
<summary><b>v0.6.18</b> — git が無いと 4 つの仕掛けが黙って no-op になる。preflight で止める</summary>

**この項目は当初、間違った根拠で書きました。** 既存プロジェクトにスクリプトを配り直したとき、
`/home/myst/projects/inventory2-api` が git リポジトリでないので「実績のあるプロジェクトが git 無しで
回っていた」と書きました。**そのディレクトリは私がその場で `mkdir -p` で作った空の入れ物**で、
本物は別の場所 (git リポジトリ、main) にありました。**パスを確かめずにプロジェクトの事実を断定した**のが
誤りです。根拠を差し替えて書き直します。

検査そのものは残します。理由は事故の記録ではなく**コードから読める事実**です:

- `wave-guard.sh` は git の外では **設計として `exit 0` で素通り**します (worktree を誤爆しないため)
- **worktree 隔離**は git が無いと作れません (並列ゴールが同じ木を踏み合う)
- 「**K ファイルが diff に含まれているか**」の確認は diff が取れません
- **`/mule-learn --share` の PR** は出せません

この 4 つは git が無いと**エラーも警告も出さずに何もしません**。それはこのプラグインの他の部分の逆です。
`deploy-guard` は deny を返し、`wave-guard` は deny を返し、`coverage-check` は exit 1 を返す。
**黙って効かない検査は、無い検査より悪い** — 効いていると思って進むからです。だから `pom.xml` の確認と
同じ扱いにしました: `scripts/preflight.sh` の最初で git を確かめ、無ければ **exit 2 で 1 件も配らない**。
落ちるときは効かない 4 つを名前で並べ、`git init` の 1 行を出します。

牙の確認: git でないディレクトリで exit 2、`git init` すると次の検査 (mvn package) まで進むことを実測。

</details>

<details>
<summary><b>v0.6.17</b> — 索引の数字を手で持つのをやめる (v0.6.15 で自分が警告した通りにずらしたので)</summary>

v0.6.15 の索引に**行数を書き、そのあとで各ファイルの見出しを 1 行縮めました**。19 個の数字が全部
1 ずつ狂いました。しかも同じコミットの記録に「索引が実体とずれると読む側はそのファイルを開かなくなる」
「PR #2 は目次の件数を 11 のまま残した」と書いてあります。**警告を書いた本人が、その場でずらせます。**

だから数字を人から取り上げました。

- **行数の列を落としました。** 行数は主題ファイルを 1 文字直すたびに動くのに、**読む側がどの主題を
  開くかには一切効きません**。持つ価値のない数字でした。
- **件数だけ残し、機械が検査します。** 件数は項目を足したときにだけ動く =`/mule-learn` が索引を
  触るのと同じ瞬間です。`scripts/knowledge-index-check.sh` が 3 つを見ます: 実体にあるファイルが
  索引に載っているか、索引の行に実体があるか、件数が `## ` 見出しの数と一致しているか。
  手で持つ数字は 28 個から 9 個に減り、その 9 個は機械が持ちます。
- `/mule-learn --share` は `gh pr create` の前にこれを通します (exit 0 が条件)。**項目を足して索引を
  直し忘れた PR は、開く前に落ちます。**
- スクリプトは `scripts/` (プラグイン本体) に置きました。**`template/scripts/` ではありません** —
  索引はプラグイン側にあり、利用者のプロジェクトには配らないので、配っても走らせる対象がありません。

牙の確認: 件数を 12 → 11 にする / 索引に無い主題ファイルを足す / 実体を消す、の 3 通りで exit 1 に
なることを実測しました (どれか 1 つでも素通りするなら、この検査は無意味です)。

`/mule-learn` からは「索引の件数を直す」という**文章の規則を消しました**。v0.6.14 の表のとおり、
機械で弾けるものを文章にしません。

</details>

<details>
<summary><b>v0.6.16</b> — plugin-root.sh が古い版を返していた (cache はセッション開始時にしか作られない)</summary>

v0.6.15 を push した直後に `bash scripts/plugin-root.sh knowledge/gotchas/munit.md` を叩いたら
**「プラグイン内に無い」と返りました**。ファイルはあります。返していたのは v0.6.8 でした。

配布経路は「作業リポジトリ → push → `marketplaces/` のクローン → `cache/<marketplace>/mule-loop/<版>/`」で、
**cache が作られるのはセッション開始時だけ**です。走っているセッションの cache は、pull 済みのクローンより
古いままになります。実測では marketplace のクローンが 0.6.15、cache の最新が 0.6.8 でした。

旧実装は候補を「cache を `sort -V -r` → marketplaces」の順に並べ、**先頭で当たったものを採用**していました。
順が版の新しさを表す前提が、この経路では成り立ちません。**全候補の `plugin.json` を読んで版が最大のものを
採る**ようにしました (`sort -V` で比較。版が読めないものは `0.0.0` 扱いで最後の手段として残す)。

これは 1 回の観測ですが、**機械で弾けるものは 1 回で弾く** (v0.6.14) 側です。放っておくと、版を上げた直後の
セッションで実行エージェントが黙って古いナレッジを読み、新しい写経元は「無い」と言われます。

検証: cache 9.9.9 + marketplace 1.0.0 → 9.9.9、cache 0.6.8 のみ + marketplace 1.0.0 → 1.0.0、
候補なし → exit 1。

</details>

<details>
<summary><b>v0.6.15</b> — 毎回読むファイルを索引と主題に割る (語を変えずに読む量を減らす)</summary>

「トークン消費を全部英語にすれば減らせるか」という問いへの答えが**減るが割る方が効く**でした。
日本語は同じ内容で英語の約 1.4 倍のトークンですが、`gotchas.md` が高い理由は**詰まるたびに 506 行を
丸ごと読んでいたから**で、語を替えても丸ごと読む構造は変わりません。**語を 1 つも変えずに**
読む量だけ減らしました。

| | 分割前 | 分割後 |
|---|---|---|
| `knowledge/gotchas.md` | 506 行 / 約 10,567 tok を**丸ごと** | 索引 927 tok + 主題 1 つ (468〜2,790) = **1,395〜3,717** |
| `knowledge/mule-basics.md` | 124 行 / 約 5,483 tok を**実行エージェントが毎回** | 索引 817 tok + 触る主題だけ (255〜1,030) |

実行エージェントが 2 主題を開く例 (flow + munit) で **5,483 → 2,106 (-62%)**、
4 主題 (flow + db + munit + error-handling) で **3,798 (-31%)**。
詰まって gotchas を引くときは中央値の主題で **10,567 → 2,027 (-81%)**。

**正直な数字も書いておきます。10 主題を全部開くと 6,780 で、分割前より 24% 増えます** (各ファイルに
出典の凡例が必要なため)。**7 主題以上読むなら損**なので、割ることそのものではなく
「索引を読んで、触る主題だけ開く」規律が効きの前提です。だから読み手側を全部直しました:
`agents/mule-executor.md` は索引の表から 1 行選んで 1 ファイルだけ開く、
`agents/mule-reviewer.md` は見る 5 つの落とし穴に対応する 3 ファイルを名前で指定、
`template/CLAUDE.md` と `mule-tdd` は「丸ごと読まない」を明記、
`mule-munit` は `gotchas/munit.md` と `basics/munit.md` の 2 つだけで足りると明記。

- `knowledge/gotchas/` 9 ファイル (build 10 件 / config 3 / munit 12 / error-handling 6 / apikit-http 3 /
  db 6 / dataweave 3 / deploy 6 / api-manager 4)。索引は**症状**から主題を選ぶ表にしました
  (「`Cannot coerce`」「properties が消える」など)。主題名だけでは、詰まっている人がどれを開くか決められません。
- `knowledge/basics/` 10 ファイル。`kind.md` (Batch / MCP / A2A) は**単独で読まれるようになった**ので、
  「これは `[S]` だけで実測がない」という但し書きをファイルの中に残しました (索引に書いても、
  ファイルだけ開いた人には届かない)。
- **分割が無損失であることを機械で確かめました。** 本文 363 行 + 83 行が主題ファイルに
  ちょうど 1 回ずつ現れることを行単位で照合 (目で見ていません)。日付と根拠つきの手書きの記録なので、
  1 行落ちても後から気付けません。
- `/mule-learn` の追記先は `knowledge/gotchas/<主題>.md` になりました。**追記したら索引の件数も直す**を
  手順に入れました。索引が実体とずれると、読む側は「合う行が無い」と判断してそのファイルを
  開かなくなり、書いた項目が誰にも読まれません (PR #2 が目次を 11 件のまま残した実例があります)。
- 主題が 1 対 1 で対応しないことは索引に明記しました。`gotchas/apikit-http` の要約は `basics/flow.md`、
  `gotchas/api-manager` の要約は `basics/deploy.md` の中にあり、`basics/flow` / `naming` / `kind` に
  対応する gotchas はまだありません (実測が無い)。**無い対応を埋めるために項目を複製しません。**

`knowledge/gotchas.md` と `knowledge/mule-basics.md` のパスは索引として残したので、
この 2 つを参照していた 18 ファイルはすべてそのまま解決します。

</details>

<details>
<summary><b>v0.6.14</b> — 「まだ 1 回だから」を機械化しない理由にしない</summary>

v0.6.13 で、進捗エージェントが自分で宣言した分担を破る件を **「n=1 なので `/mule-learn` の
2 回ルールに反する」として規則に留めました**。これが間違いでした。**直せるのに直さない理由**に
なっていたので、方針ごと変えました。

**昇格に必要な回数を、回数ではなく昇格先で決めるようにしました。**

| 昇格先 | 必要な回数 | 理由 |
|---|---|---|
| hook / script / 写経元 | **1 回** | 読む負担がゼロ。効く場所に置くだけで、増えても誰も遅くならない |
| 文章の規則 (`CLAUDE.md`、スキル、レビュー観点) | **2 回** | 読む負担がある。1 回の事故で増やすと肥大して読まれなくなる |

元の 2 回ルールの心配は「規則が増えて CLAUDE.md が読まれなくなる」でした。その心配は**文章に
だけ**当たります。hook は誰も読まないので、1 回で作って損がありません。2 回目を待つのは
**文章にしかできないとき**だけ、逆に 2 回以上出ていても機械で弾けないなら文章にします。

**そのうえで、留保していた件を機械にしました: `scripts/wave-guard.sh` (PreToolUse hook)。**

進捗エージェントは配布時に `.claude/wave-owned` へ「パス<TAB>ゴール id」を書きます。hook が
それを読み、**進捗エージェントの Edit / Write を deny します**。これは頼み事ではなく
**自分を縛る鍵**です (破ったのは宣言した側なので、宣言が守られる前提では書けない)。
取り込みが全部終わったら消し、そこで初めて共有ファイルへまとめて追記します。

「誰を弾くか」は **git 自身の信号**で決めていて、パスの形を推測しません。リンク worktree の
`--git-dir` は `<repo>/.git/worktrees/<名前>` で `--git-common-dir` と異なり、メインの作業ツリーでは
一致します。だから**実行エージェント (worktree) は素通りし、進捗エージェント (メイン) だけが
弾かれます**。`.claude/wave-owned` が誤ってコミットされて worktree に現れても実行エージェントを
塞ぎません (実測で確認)。消し忘れた宣言は **12 時間で無効**になります — 中断した波の残骸が以降の
書き込みを黙って塞ぐと、それ自体が新しい `loop-ops` になるからです。

hook が見るのは Edit / Write だけで、`echo >> file` のようなシェル経由の追記は弾けません
(コマンド文字列からの判定は誤検知が多い)。そこは `/mule-run` の禁止の文章が受け持ちます。

実装中に踏んだもの: **python の本体を heredoc で渡すと hook の JSON (stdin) を食われます。**
`json.load(sys.stdin)` では読めず、deny が一度も出ませんでした。stdin を先にファイルへ受けてから
渡します (`stop-guard.sh` と同じ形)。

検証 10 ケース: 相対パス / 絶対パス / 深い cwd から / 宣言外は素通り / worktree は素通り /
12 時間より古い宣言は無視 / 宣言ファイル無し / git 管理外 / **誤ってコミットしてもメインだけ deny** /
worktree に現れても素通り。
</details>

<details>
<summary><b>v0.6.13</b> — K ファイルの名前を手で決めさせない (loop-ops の未対応 2 件のうち 1 件)</summary>

v0.6.12 の分類し直しで 1 位になった `loop-ops` 10 件を見ると、worktree の基点 (v0.6.4/0.6.7)、
初期コミット (`/mule-init` 6b)、台帳の二重記録 (v0.6.5) は手当て済みで、**未対応は 2 件**でした。

**1 件目: K ファイルの番号衝突。** 並列の実行エージェントが同じ `K-NNN.md` を独立に選び、
取り込みで衝突した記録です。名前にゴール id を入れる対処は既に一部の文書に入っていましたが、
**プラグインの中で 2 つの流儀が並走していました**:

| 場所 | 書かれていた形 |
|---|---|
| `template/CLAUDE.md` (毎セッション読まれる) | `K-NNN.md` ← 衝突する形 |
| `skills/mule-learn/SKILL.md` | `K-NNN.md` ← 同じ |
| `agents/mule-executor.md`、`skills/mule-run/SKILL.md` | `K-<ゴール id>-<連番>.md` |

実際のプロジェクトでは **4 通りに散っていました** (`K-001.md` / `K-009-1.md` / `K-T-001-1.md` /
`K-T-003-1.md`)。しかも `K-001.md` は 2 つのプロジェクトの両方にありました。
**手で選ばせる限り揃いません。**

`scripts/k-new.sh` を追加し、名前を機械に決めさせました。

```bash
bash scripts/k-new.sh T-003   # → knowledge/K-T-003-1.md (既にあれば -2)
bash scripts/k-new.sh learn   # → knowledge/K-learn-1.md  (/mule-learn の昇格の記録)
```

ゴール id が名前に入るので**別のゴールとは構造的に衝突しません**。文書 5 か所を 1 つの流儀に
揃え、`K-NNN.md` を残らず消しました。K ファイルの**中身の形も 2 通りあった**ので
(`mule-learn` は昇格先と件数、`executor` は根拠のコマンドと調べた場所) 1 つにし、
昇格先と件数は `/mule-learn` の K に限ると明記しました。

**ファイルは作らずパスだけ出します。** 空の K ファイルが diff に現れると、`/mule-run` の
「K ファイルが diff に含まれているか」の確認が「学びの記録あり」と誤判定するためです
(牙の無い検査を作らない)。

**2 件目 (進捗エージェントが自分で宣言した分担を破る) は規則に留めました。** `/mule-run` の禁止に
「波の中で『このゴールが触る』と宣言した追記型ファイルを進捗エージェント自身が触ること」を足し、
完了処理の追記は全ゴールを取り込み終えてからまとめて行うことにしました。**機械では弾いていません。**
まだ 1 回しか出ておらず、`/mule-learn` の「2 回以上のものだけを候補にする」に反するからです。
1 回の事故で機械を作ると、どのファイルが対象かも分からないまま配管が増えます (それ自体が
新しい `loop-ops` になる)。2 回目が出ればファイルが特定できるので、そのとき hook にします。
</details>

<details>
<summary><b>v0.6.12</b> — 分類し直したら 1 位が変わった (uncategorized 13 件の回収)</summary>

finance-api の台帳 41 件のうち **18 件が固定語彙の外**にありました。`uncategorized` 13、
`toothless-assertion` 4、`connector-usage` 1。`/mule-learn` の手順 0 はこれを毎回片付ける段ですが、
一度も実行されていませんでした。自作の値は集計で別物として扱われるので、**記録はされたが数えられず、
数えられないから昇格されない**行として溜まっていました。

各行に `vocabulary_gap` (書き手が「本当はこの語がほしい」と書いた欄) が残っていたので、それを使って
18 件を分類し直しました。内訳は `loop-ops` 6、`test-toothless` 5、`connector-behavior` 4、
`secret-leak` 1、そして既存語彙に無い 2 件。

**順位が変わりました。**

| | 分類前 | 分類後 |
|---|---|---|
| 1 位 | `munit-coverage` 8 | **`loop-ops` 10** |
| `loop-ops` | 4 | 10 |
| 語彙外 | 18 | 0 |

語彙外の 6 件が worktree の基点、K ファイルの衝突、台帳が書かれない、配布の分担破り —
**すべて `loop-ops`、つまり昇格先がプラグイン本体への PR** でした。数える前に手順 0 を飛ばすと、
一番大きいクラスタが見えないまま「次は MUnit」と判断することになります。この実例を手順 0 に
書き足して、飛ばせないようにしました。

**語彙を 1 つ増やしました: `environment-fact`。** 実接続して初めて分かった接続先やドライバの事実
(現在スキーマがどちらに着地するか、`getSQLState()` が常に null、TIMESTAMP がどの型で届くか)。
既存のどれでもなく、**昇格先が `gotchas.md` ではない**ことが要点です。この接続先でしか成り立たない
測定値なので、`context/environment/` に置きます。プラグインに持ち出すと嘘になります。
`vocabulary_gap` には `environment-fact` / `external-driver-quirk` / `environment-setup` の 3 案が
書かれていましたが、語彙を増やしすぎると数えられなくなるので 1 つに統合しました。

`category` → 追記先の表に `environment-fact` と `loop-ops` の行き先も明記しました。

**`test-toothless` 5 件の昇格**: 5 件とも根は 1 つ (「検査が走ったことを確かめずに結果を読んだ」) で、
`mule-munit` の「牙があるか確かめる」に **3 つ目**を足しました — 行番号を決め打ちした `sed` で細工すると
行がずれていて**細工が 1 文字も当たらず**、緑を「牙が無い」と誤読しかけた実例です。細工は行番号ではなく
内容で当て、当てた直後に細工後の行を表示して確認する。

分類し直した台帳は finance-api 側にあります (変更前の値を `category_was`、判断理由を
`category_reason` として各行に残したので、あとから検算できます)。
</details>

<details>
<summary><b>v0.6.11</b> — 同じ指紋を 6 回踏んでいた。文章ではなく写経元を置く (mule-munit)</summary>

台帳 62 件のうち **17 件が MUnit** で最大のクラスタでした。内訳は `mock-when` 漏れ、カバレッジ未達、
牙の無い assert。しかもそのうち **7 件が同一の指紋** — APIkit の振り分け flow
(`<method>:\<path>:<config 名>`) を `flow-ref` するとカバレッジ検査が要求するのに attributes が
無くて動かない、という 1 つの問題です。6 件目の記録に理由がそのまま書かれていました:

> 6回とも同じ形で解決できており、reference/ に写経元が無いために毎回この指紋を踏んでいる。

さらに 7 件目 (`test-toothless`) が、その 6 回の回避策自体の問題を挙げていました。attributes 無しで
`flow-ref` すると NPE で `global-error-handler` の `ANY` 枝 (500) に落ちるので、`vars.httpStatus` が
non-null であることだけを assert すればカバレッジは通る — **通るが、リクエスト内容による分岐を
何も検証していない**。その形のテストが 7 本残っていました。

**`template/reference/router-test.xml` を追加しました。** attributes を型付けして振り分け flow を
直叩きし、**正常応答の中身まで assert する**形です。パス変数あり / 本文あり (mediaType 込みの flow 名) /
検索系の 3 形を入れています。

型付け方式は finance-api の main flow で実証済みでしたが、**振り分け flow に対しては誰も実際に流して
いなかった**ので (gotchas は「同じ問題」と書いているだけ)、実測しました:
`get:\inventory\(inventoryId):inventory2-api-config` を型付け attributes で叩き、
`payload.inventoryId` と `payload.warehouseCode` まで assert して **1 件 pass**。期待値を壊すと
**Failed: 1 / exit 1** で、牙もあります。弱いテストで代替する必要はありませんでした。

検索系の例外も写経元に入れました。`queryParams` が全て任意項目の振り分け flow では、attributes 無しでも
DataWeave の null 伝播でエラーにならず**正常完走してしまう**ため、「500 に落ちる」前提の回避策は
そもそも成り立ちません (T-003 の実測)。

**`skills/mule-munit/` は薄く保っています。** gotchas.md は根拠と日付つきの一次記録なので、
スキルは「踏む順のチェックリスト」と「写経元の在処」だけです。書く前に 30 秒で確かめる 5 つ、
コネクタの戻り値の形、カバレッジ検査が何を見ていないか、**書いたテストに牙があるかの実測 2 手**
(期待値を壊して落ちるか / 狙った case 名が失敗として出力に現れるか — 前処理が先に落ちて狙った
チェックが一度も走らないまま exit 1 になる形が実際にあった)、MUnit で検証できないもの
(トランザクションの commit/rollback、SQL 文、listener の直列化)。

**`/mule-learn` の昇格先に主題別スキルを足しました。** これは前回「付いてくる設計上の宿題」として
挙げたもので、gotchas を主題別に割ると新しい指紋の追記先が決まらなくなります。category ごとの
追記先の表 (`munit-*` / `test-toothless` → `skills/mule-munit/`) と、
**同じ形で 3 回以上解決しているものは文章ではなく `template/reference/` の写経元にする**という規則を
入れました。今回の 6 回がまさにそれです。

`mule-tdd` の Red 節と `agents/mule-executor.md` の読むものからも参照しています
(v0.6.10 で入れた `plugin-root.sh --skill` 経由)。
</details>

<details>
<summary><b>v0.6.10</b> — 実行エージェントは Skill ツールを持たない。スキルは名前ではなくパスで渡す</summary>

`agents/mule-executor.md` は「最初に **Skill ツールで** `mule-tdd` を読み込み」と指示していましたが、
同じファイルの `tools:` は `Read, Edit, Write, Bash, Grep, Glob` で **Skill が入っていません**。
ハーネスが解決したツール一覧にも出ません。実行ループの一番最初の 1 行が実行不能でした。
policy 段の「最初に同梱の公式スキルを読みます: `secure-api`、`apply-policy-to-api-instance`」も
名前だけでパスが無く、辿れませんでした。

しかも**その 3 つはこの環境に存在しません**。`scripts/setup-deps.sh` が
`npx skills add mulesoft/mulesoft-dx` で入れようとしているものですが、`~/.claude` を探しても
`secure-api` / `apply-policy-to-api-instance` / `build-mule-integration` は 1 つも見つかりません。
**無いものを名前で読ませていた**ので、実行エージェントは探し回って時間を溶かすだけでした。

パスの実測が 3 つ:

- `${CLAUDE_PLUGIN_ROOT}` は**ハーネスが読み込み時に展開する**。skills の本文で確認したところ
  `/home/…/.claude/plugins/cache/mule-loop-marketplace/mule-loop/0.6.7/` に置き換わっていた。
- しかし **シェルの環境変数には無い** (`env` に存在しない)。`cat $CLAUDE_PLUGIN_ROOT/...` は必ず空振りする。
- **生のファイルとして Read すると展開されない。** Skill ツールを使わない実行エージェントは
  SKILL.md をそのまま読むので、中の `${CLAUDE_PLUGIN_ROOT}` は文字列のまま届く。
- 展開先は **版つきのキャッシュ**。得た絶対パスを台帳や K ファイルに書き写すと次の版で開けなくなる。

`scripts/plugin-root.sh` を追加しました。

```bash
bash scripts/plugin-root.sh                       # プラグインの実体 (最新版) の絶対パス
bash scripts/plugin-root.sh knowledge/gotchas.md  # その中のファイルの絶対パス
bash scripts/plugin-root.sh --skill secure-api    # スキルの SKILL.md の絶対パス
```

見つからなければ **何も出さず exit 1**。executor には「exit 1 なら入っていないので**そこで諦めて**
gotchas → `reference/mule-schema/INDEX.md` → マニュアルの順に戻る。**探し回らない**」と書きました。
`mule-tdd/SKILL.md` の冒頭にも、生で読んでいる場合は展開されていないという注記を入れ、
自力で解決できるようにしています。

`${CLAUDE_PLUGIN_ROOT}` が **agents/*.md でも展開されるかは未検証**です (エージェントを起動しないと
確かめられない)。ただしどちらに転んでもこの修正で通ります — 展開されていればそのまま使い、
文字列のままなら `plugin-root.sh` で直すよう両方書いてあります。

7 ケースで検証 (最新版キャッシュの選択 / プラグイン内ファイル / 同梱スキル / 未導入の公式スキル →
exit 1 / 無いファイル → exit 1 / `~/.claude/skills` 側の外部スキル / `CLAUDE_PLUGIN_ROOT` が
壊れた値でも動く)。finance-api で「スキルを解決 → 生で読む → 中の相対パスを解決」の通しも確認しました。
</details>

<details>
<summary><b>v0.6.9</b> — コネクタの要素名を推測させない。~/.m2 の jar から版の一致したスキーマを生成する</summary>

スキルは 8 本ともループの運用で、**Mule アプリの書き方を教えるものが 1 本もありません**でした。
ドメイン知識は `knowledge/mule-basics.md` 124 行と `gotchas.md` 523 行、それに `template/reference/`
だけで、届け方は「basics は毎回読む、gotchas は詰まったら読む」。DB を触らないゴールでも DB の節を
読み、MUnit で詰まったときに 52 件中 45 件が無関係な 523 行を開く形で、知識が増えるほど 1 ゴール
あたりのコストが上がる構造でした。

その第一歩として `scripts/schema-index.sh` を追加しました。コネクタの XSD と説明は jar の
`META-INF/` に入っていて版ごとに中身が違うので、**手で書き写すと必ずずれます**
(`gotchas.md` の「コネクタの GAV を推測しない」を人間の側で破ることになる)。jar から抜けば、
そのプロジェクトが実際に解決した版と一致します。

- 一覧は `mvn -o dependency:list` から取ります。pom を正規表現で読むと `${...}` の版と推移的な
  コネクタを落とします (実測: 直接依存 3 件しか取れないところ、`mule-sockets-connector` を含む
  解決済み 99 行が取れた)。スコープは絞りません (`-DincludeScope=compile` を付けると
  **MUnit と db コネクタが消えます**)。**ネットワークには触りません。**
- ランタイムの extension model は依存一覧に出てこない (ランタイムが提供する) ので、
  `<app.runtime>` から補います。`~/.m2` にその版が無ければ同じ major.minor の最新に落とします
  (`minMuleVersion` 4.12.0 と実際に置かれている 4.12.2 がずれるため)。
- 出力は `reference/mule-schema/` に **コミットします**。worktree は `origin/main` から切られるので、
  コミットしないと実行エージェントに届きません (v0.6.7)。副産物としてコネクタの版が変わったことが
  diff で見えます。実測で **21 ファイル / 9,638 行 / 560 KB** — 全部入りではなく、そのプロジェクトが
  使う版だけです。
- `INDEX.md` に表と「操作の一覧」(`mockWhen`、`bulkInsert` など jar から抜いた操作名) を書き、
  **全部読まず 1 ファイルだけ開く**よう実行エージェントに指示しました。`mule-core-common.xsd` は
  3,503 行あるので頭から読ませません。

**Node は使いません。** Windows も macOS も既定で入っておらず、このプラグインの既存の前提は
bash + python3 + jq です。jar は zip なので `python3` の `zipfile` で直接読めて、依存はゼロ増です。

`/mule-init` の 5c (5b で `~/.m2` が埋まった直後、6b の初期コミットの前) と `preflight.sh`
(`pom.xml` が `INDEX.md` より新しいときだけ再生成) から呼びます。**preflight ではここの失敗で
波を止めません** — 索引は速くするための補助で、土台の判定は `mvn package` の結果だからです。

finance-api と inventory2-api の 2 プロジェクトで検証しました。異常系も: `pom.xml` 無し → exit 2、
依存が未解決 → exit 2 と復旧手順、`~/.m2` に無い版 → 同 major.minor へ縮退、3 つの jar が同名で持つ
`mule.schemas` の衝突 → 1 本に統合。生成した 21 ファイルは全て `xmllint` を通ります
(GAV のコメントは XML 宣言の**後ろ**に入れる。前に置くと well-formed でなくなる)。
</details>

<details>
<summary><b>v0.6.8</b> — デプロイの承認は毎回押すものではなく、ファイルに 1 回書くもの</summary>

デプロイのたびに人の承認を取っていました。二段階あって、`template/.claude/settings.json` の
`ask` に `Bash(mvn * deploy*)` があるので**コマンドのたびに**プロンプトが出て、さらに
`mule-deploy` のゲート 2 が「人が**この会話で**明示的に指示すること」を求めるので**会話のたびに**
言い直しが要りました。許可はもともと `context/deployment/authorizations.yaml` に書いてあるのに、
同じことを二度確かめていたわけです。判定者を人から機械に移すのがこのリポジトリの作り方なのに、
デプロイだけ人の Enter に頼っていたのは筋が通っていませんでした。

`scripts/deploy-guard.sh` を PreToolUse hook として追加しました。`mvn ... deploy` /
`-DmuleDeploy` / `anypoint-cli ... deploy` を捕まえ、`authorizations.yaml` の
`deploy.sandbox` が `allowed` で、環境名が Production 系でなければ **allow を返して
プロンプトを出しません**。環境名は `sandbox.yaml` だけでなく **`pom.xml` の `<environment>`**
も見ます。実際に `mvn` が使うのは pom なので、sandbox.yaml が Sandbox でも pom が Production を
指していれば止まります。両方空のときも止めます（空を通すと本番に向く事故を検出できないため）。
`settings.json` の `ask` から `mvn` / `anypoint-cli` の deploy を外し、判定を hook に一本化しました。
ゲート 2 は「台帳に `stage: deploy` のゴールがあること」に置き換えています（台帳の外で作業しない、
という既存の規律と同じもの）。`template/CLAUDE.md` の同じ記述も直しました（CLAUDE.md は毎セッション
読まれ SKILL.md より強いので、ここが古いままだと結局聞かれ続けます）。

`authorizations.yaml` は **hook 入力の `cwd` から git ルートまで遡って**探します。相対パスで開くと、
monorepo や worktree で作業ディレクトリがプロジェクト直下でないときに見つけられず、**無言で素通り
（＝無防備なデプロイ）** になります。v0.6.7 で実際に踏んだ相対パス解決の事故と同じ形です。
コマンドが絶対パスへ `cd` してから走る形（`/mule-run` が実行エージェントに配る形）なら、その `cd` 先を
起点にします。遡っても見つからなければ mule-loop のリポジトリではないので、何も言わずに通常の判定に返します。

**本番の防波堤は弱くなっていません。**むしろ文章から機械に変わりました。以前の「Production 名の
環境には決して向けない」は SKILL.md の文であって、守るかどうかは書き手の注意力に依存していました。
今は hook が deny を返し、コマンド自体が実行されません。

捕まえる形は `mvn clean deploy` だけでなく `mvn mule:deploy` / `mvn deploy:deploy` も含みます
（`:` の後ろでも deploy と読む）。Production 系の判定には `prd` も入れました（Anypoint でよく使う略記で、
`prod` に含まれません）。

**end-to-end で実測しました。** `--permission-mode default` の実セッションで、許可リストに無い
`touch` を含むコマンドが `allowed` のときは**プロンプト無しで実行され**、`denied` のときは
**hook の deny で実行されず理由が返る**ことを確認しています。スクリプト単体は 17 ケース
（denied のまま / 非デプロイコマンドの素通り / `deploy:` と `policy:` の同名キーの取り違え /
Production 名 / `PRD` / pom だけ Production / 環境名が空 / `mvn mule:deploy` / anypoint-cli /
`cd` 前置き / 深い階層からの遡り / mule-loop 以外のリポジトリでは介入しない、など）。
</details>

<details>
<summary><b>v0.6.7</b> — worktree は origin/main から切られるので、ローカルのものは実行エージェントに届かない</summary>

v0.6.4 では「配る前にコミットすれば、ゴールファイルと前の波の成果が worktree に入る」と書きましたが、
**誤りでした**。3 回の実測で、worktree は **`origin/main`** から切られることが確定しました。
ローカルの HEAD でも、現在ブランチの upstream でもありません。
(1) 未 push のローカルコミットが 1 つ先の状態 → worktree は origin/main。
(2) push して origin/main を進めると worktree も**新しい** origin/main に追随 → 「セッション開始時点で固定」ではない。
(3) upstream を push 済みの feature ブランチをチェックアウトして実行 → それでも origin/main。
**ブランチを切っても解決しません。** push すれば届きますが、届け先は `main` しかなく、
それこそゲート 2 が守っているものです。該当ブロックは注釈追記ではなく**書き換え**ました
(配る前のコミットはチェックポイントであって、worktree には何も届けない)。

対処は 2 つです。配布プロンプトに**ゴールの中身を丸ごと貼り**、**プロジェクト直下の絶対パス**を渡して
「まずそこへ `cd` する」と明示しました。monorepo では worktree の作業ディレクトリがリポジトリ直下で
プロジェクト直下ではないため、相対パス `tasks/T-001.md` が別プロジェクトに解決されて
無関係なファイルを書き換える事故が実際に起きています。もう 1 つは隔離を条件付きにしたことで、
remote が無いとき (**未検証**。遅れる対象が無いので問題無いはずだが実測していない)、または
`HEAD == origin/main` かつ作業ツリーがきれいなときだけ `isolation: "worktree"` を使い、
それ以外は隔離せず作業ツリー上で直列に実行します。**実質「隔離と並列が効くのは最初の 1 波だけ」**です
(その波の dispatch コミットで必ずローカルが先行するため)。判定に `blocked_by` を使わないのは意図的で、
独立なゴールでも `pom.xml` / `global.xml` / RAML は共有しており、同じように古くなるからです。

併せて PR #5 (APIkit の gotcha を main flow だけでなく振り分け flow にも広げる) をマージし、
その PR が 11 のままにしていた gotchas 目次の `MUnit` の件数を 12 に直しました。

</details>

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
