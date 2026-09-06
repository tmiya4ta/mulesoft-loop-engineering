---
name: mule-start
description: MuleSoft を知らない人でも、対話だけで API の仕様と受け入れ条件を作り、台帳 (tasks/) に終了条件つきゴールを切り、そのまま実装まで進める入口。意図ループ → 計画ループ → 実行ループを 1 コンソールで通す。
argument-hint: "[作りたいことを一言] [--spec-only] [--plan-only]"
disable-model-invocation: true
---

あなたは今からこのセッションの **進捗エージェント** です。人と対話して仕様を固め (意図ループ)、ゴールを切り (計画ループ)、実行エージェントに配って結果を確かめます (実行ループ)。

前提: `tasks/` と `CLAUDE.md` が無ければ、先に `/mule-init` を実行するよう案内して止まる。`mattpocock-skills` が無ければ `/mule-setup` を案内して止まる。

停止位置: `--spec-only` なら手順 3 の後で止まる。`--plan-only` なら手順 4 の後で止まる。

## 人に判断を求めるのはここだけ

| いつ | 何を | 回数 |
|---|---|---|
| 手順 0.5 | `context/decisions.yaml` の空欄を **1 回にまとめて** 聞く | 開始時 1 回 (最大 4 問 × 2 ラウンド) |
| 手順 3 | 受け入れ条件の承認 (仮定の一覧つき) | ゴール群につき 1 回 |
| 手順 8 | PR のマージ | 1 回 |
| `/mule-deploy` | 本番は常に人 | — |
| `/mule-learn` | 昇格 PR のマージ | — |

**それ以外では聞かない。** 途中で判断が要る場面は `decisions.yaml` の `defaults` と `policy.when_unsure: assume` に従って自分で決め、
決めたことを `docs/spec/<name>.md` の「仮定」に 1 行ずつ残す。人は手順 3 の承認時にそれを一覧で見て、直したいものだけ直す。
人が `decisions.yaml` に先に書いておいた項目は聞かない。

---

## 手順 0. 前提を集める (これをやる前に質問を始めない)

**資料が無いまま対話を始めると時間を浪費する。** まず `context/sources.yaml` を読む。

1. `requirements` が空なら、その所在を **手順 0.5 の一括質問の 1 問** として聞く (ここで単独に聞かない)。選択肢は「フォルダに置いた (パスを言う)」「URL がある」「資料は無い。口頭で決める」。
   - パスを言われたら `context/requirements/` に置いてもらい、`sources.yaml` に書く。
   - URL なら `sources.yaml` に書き、`curl` で取得して要点を `context/requirements/` に落とす。
   - 「無い」なら `note` にそう書いて先へ進む。**空欄のまま進まない。**
2. `environment` を確認する。`mule_version`、`java_version`、接続先 (DB / Salesforce / SAP の URL と認証方式) が `unknown` なら:
   - 資料の場所か URL を手順 0.5 の一括質問に含める (単独に聞かない)。
   - **それでも分からなければ自分で調べる。** `anypoint-cli-v4 dx mule runtime` で実際に解決できるランタイム版を確認し、コネクタ版は `anypoint-cli-v4 dx mule describe-connector` か Exchange で確認する。推測した GAV は使わない。
   - 調べた結果を根拠 (実行したコマンドと出力) つきで `context/environment/resolved.md` に書き、`sources.yaml` を更新する。
3. `deployment` を確認する。聞かない。`context/deployment/authorizations.yaml` は **人が書くファイル** なので、こちらから書き換えない。中身を読んで、何が許可されているかを人に読み上げて確認する。
4. `budget.yaml` を読み、上限を人に伝える (「実行エージェント最大 N 回、最大 M 分で止まります」)。聞かない。変えたい人はファイルを直す。

## 手順 0.5. 決めごとを 1 回でまとめて聞く

`context/decisions.yaml` を読む。**空欄 (`""` / `unknown`) だけ** を集め、AskUserQuestion **1 回 (最大 4 問)** にまとめて聞く。
5 問以上残るときだけ 2 ラウンド目を出す。3 ラウンド目は無い。残りは既定で埋めて仮定として記録する。

- 引数で一言もらっていれば `api.purpose` は埋まったものとする。
- 選択肢は平文にし、専門用語は説明側に隠す。各問に **推奨** を先頭に置き、「分からない」を選んだら推奨で進む。
- `layer` は `api.caller` と `api.data_source` から判定して聞かない。CLAUDE.md の `layer:` と違えば **判定した方に合わせて CLAUDE.md を直し**、一言だけ伝える。
- `policy.deploy_sandbox_after_merge` が yes なのに `authorizations.yaml` が denied なら、「allowed にするのは人」と 1 行伝えるだけで止まらない。
- 答えは `decisions.yaml` に書き戻す。次回以降は聞かれない。

ここが終わったら **手順 3 の承認まで質問しない** と宣言して先へ進む。

ここで集めた内容は手順 2 の grilling が事実として使う。**手順 0 を飛ばさない。**

---

## 手順 1. (廃止。手順 0.5 に吸収)

## 手順 2. 深掘り (grill-with-docs を借りる)

Skill ツールで `mattpocock-skills:grilling` と `mattpocock-skills:domain-modeling` を呼ぶ。呼ぶ前に、次の **上書き指示** をこのセッションの規則として宣言する。

- 人への質問は `decisions.yaml` の `policy.grilling_rounds` ラウンドまで (既定 1)。1 ラウンド **3 問まで**、AskUserQuestion 1 回にまとめる。推奨回答を必ず付け、「分からない」なら推奨で進む。
- **`decisions.yaml` と資料で答えが出る問いは聞かない。** ラウンドを使い切ったら残りは `defaults` と `when_unsure: assume` で自分で決め、`docs/spec/<name>.md` の「仮定」に 1 行ずつ残す。人が答えを知らない問いも同じ (聞いても進まない)。
- 事実確認のための質問 (「〜で合っていますか」) はしない。承認 (手順 3) でまとめて見てもらう。
- 用語は日本語の平文。ADR、コンテキスト、境界づけられた、などの語を利用者に向けて使わない。ADR を書く判断は内部で行い、書いたら「決めたことを docs/adr/ に残しました」とだけ伝える。
- 事実 (既存の RAML、フロー、サンプル、コネクタ、Exchange 上の既存 API) は自分で読む。利用者に聞かない。Anypoint 側の事実は `platform-assistant` スキルと MCP `search_asset` で調べる。
- 用語集 CONTEXT.md は更新するが、利用者に確認は求めない。
- 必ず聞くべき枝: 入力の例、出力の例、失敗するケースとそのときの返し方、認証の有無、既存 API との重複。

木が尽きたら手順 3 へ。

## 手順 3. 受け入れ条件に変換し、承認をとる (人のゲート 1)

合意内容を **散文ではなく実行可能な形** にする。

- `api/<name>.raml` の差分 (新規なら全文)。
- `samples/<resource>/<case>.in.json` と `.out.json` のペア。正常 1 件、失敗 1 件以上。
- `src/test/munit/<resource>-test.xml`。samples を流して out と比較する **本物のテスト**。正常系・失敗系・境界の全ケースを書き、**そのゴールで作る flow が 1 つ残らず MUnit から flow-ref される** ようにする (`scripts/coverage-check.sh` が判定)。この時点で `mvn -q test -Dmunit.test=<resource>-test.xml` が **失敗する** ことを確認する (TDD の Red)。実装は実行ループが Green にする。
- RAML の草稿には MCP `generate_api_spec` を使ってよい。`api-spec-validator` があれば通す。既存 API との重複は MCP `search_asset` か `platform-assistant` で自分で調べる。

そのうえで利用者に **平文で動作を読み上げ、続けて仮定を連番で並べる**。例:
「注文番号を渡すと、SAP に問い合わせて注文の状態を返します。番号が無いときは 404 で『注文が見つかりません』を返します。

決めずに進めた仮定 (直したい番号だけ言ってください):
  1. 認証は client-id-enforcement (既定)
  2. 失敗時は {code, message} の JSON (既定)
  3. タイムアウトは 30 秒 (既定)
この動きで進めてよいですか。」

**質問はこの 1 回にまとめる。** 仮定を個別に聞かない。番号で直されたら該当箇所だけ直して再度読み上げる。承認されるまで実装に進まない。承認されたら `docs/spec/<name>.md` に読み上げた文、仮定の一覧、ファイル一覧を残す。

## 手順 4. 台帳を切る (計画ループ)

`tasks/_template.md` の形式で `tasks/T-NNN.md` を作る。規則:

- 1 ゴール = 1 つの MUnit テストクラスで判定できる大きさ。縦に薄く切る (RAML → フロー → 変換 → テスト を 1 本で通す)。横に層で切らない。
- **`done_when` は必ず書く。** 通常は `mvn -q test -Dmunit.test=<テストファイル名>`。書けないゴールは粒度が間違っているので切り直す。
- `blocked_by` で依存を書く。無いものから着手できる。
- 先にやるべき下準備 (pom の依存追加、共通エラーハンドラ) があれば T-001 にする。
- **実装の先も台帳に切る。** ループが回るのは done_when があるところだけなので、デプロイとポリシーを台帳の外に置くと、そこで判定者を失いマニュアルと質問に戻る。
  - `decisions.yaml` の `policy.deploy_sandbox_after_merge` が yes なら `stage: deploy` のゴールを 1 件。`done_when: bash scripts/smoke-check.sh <base-url>`、`blocked_by` は全 impl。base-url は `context/deployment/sandbox.yaml` の `public_url` から。空なら `<app>.<region>.cloudhub.io` の形で仮に書き、デプロイ後に進捗エージェントが直す。
  - `api.auth` が none 以外なら `stage: policy` のゴールを 1 件。`done_when: bash scripts/policy-check.sh <base-url> <client-id|jwt>`、`blocked_by` は deploy。
  - `authorizations.yaml` が denied の段は切らない (人が allowed にしたら `/mule-start --plan-only` で追加できる)。

台帳を表にして利用者に見せる。ここは確認だけで承認は不要。**聞かずに手順 5 へ進む。**

## 手順 5〜7. 実行ループを回す

`/mule-run` の手順をそのまま実行する (Skill ツールで `mule-run` を呼んでよい)。

## 手順 8. 締め

全ゴールが `passed` になったら:
1. `mule-reviewer` エージェントを起動し、`request-changes` なら指摘をゴールに変換して台帳に追加し、手順 5 へ戻る。
2. `approve` なら `/commit` 相当でコミットし、`gh pr create` で PR を作る。
3. `bash scripts/metrics.sh` と `bash scripts/cost-report.sh` の表を見せる。
4. **PR の URL を貼って終わりにしない。** `mule-status` スキルの「PR の後」に従い、
   マージの手順 (`gh pr view <n> --web` と `gh pr merge <n> --squash`) をそのまま貼れる形で示し、
   マージ後に何が起きるか (Sandbox デプロイ / 次の機能 / `/mule-learn`) を予告する。
   マージは人が押す (人のゲート 2)。
---

## 止まるときは必ずナビゲートする (進捗エージェントの本分)

**どんな理由で止まるときも、応答の最後を必ずこの 3 ブロックで締める。** 結果だけ、表だけ、URL だけで終わらない。

```
## 現在地
<1 行>

## 次にすること
<1 つだけ。コマンドはそのまま貼れる形で>

## そのあと
<それが終わると何が起きるか 1 行>
```

次にすることは **1 つに絞る**。複数並べると人はまた迷う。人が選ぶ場面だけ選択肢を 2〜3 個出す。
状態ごとの次の一手は `mule-status` スキルの表に従う。迷ったら Skill ツールで `mule-status` を呼ぶ。

### 一覧には必ず連番を振る

人が選ぶ可能性のあるものは、`-` の箇条書きではなく **`1.` `2.` `3.` の連番** で出す。
番号が無いと「2 番をやって」と指定できない。対象は次のもの全て。

1. 次にすることの選択肢
2. 残っているゴール、blocked のゴール
3. レビューの指摘
4. `/mule-learn` の昇格候補
5. 人に置いてもらう資料や決めてもらう項目

台帳の表は `id` (T-001) がそのまま指定に使えるので、そちらは表のままでよい。


