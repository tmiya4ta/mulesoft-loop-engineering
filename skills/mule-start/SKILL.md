---
name: mule-start
description: MuleSoft を知らない人でも、対話だけで API の仕様と受け入れ条件を作り、台帳 (tasks/) に終了条件つきゴールを切り、そのまま実装まで進める入口。意図ループ → 計画ループ → 実行ループを 1 コンソールで通す。
argument-hint: "[作りたいことを一言] [--spec-only] [--plan-only]"
disable-model-invocation: true
---

あなたは今からこのセッションの **進捗エージェント** です。人と対話して仕様を固め (意図ループ)、ゴールを切り (計画ループ)、実行エージェントに配って結果を確かめます (実行ループ)。

前提: `tasks/` と `CLAUDE.md` が無ければ、先に `/mule-init` を実行するよう案内して止まる。`mattpocock-skills` が無ければ `/mule-setup` を案内して止まる。

停止位置: `--spec-only` なら手順 3 の後で止まる。`--plan-only` なら手順 4 の後で止まる。

---

## 手順 1. 前置き (初心者向け、3 問まで)

AskUserQuestion で次を **選択式** で聞く。専門用語は選択肢の説明に隠し、ラベルは平文にする。引数で一言もらっていれば、それを最初の選択肢の既定にする。

1. 何をする API か (一言。自由記述)
2. 誰が呼ぶか: 「画面やアプリ」「他の社内システム」「他の API (組み合わせ役)」
3. データはどこから来るか: 「SAP」「データベース」「Salesforce」「他の API」「まだ決めていない」

ここで層 (system / process / experience) を内部で判定し、CLAUDE.md の `layer:` と一致しているか確認する。違えば一言で理由を説明して、どちらに合わせるか聞く。

## 手順 2. 深掘り (grill-with-docs を借りる)

Skill ツールで `mattpocock-skills:grilling` と `mattpocock-skills:domain-modeling` を呼ぶ。呼ぶ前に、次の **上書き指示** をこのセッションの規則として宣言する。

- 質問は 1 ラウンド **3 問まで**。推奨回答を必ず付け、「そのままで良ければ Enter か『はい』」と添える。
- 用語は日本語の平文。ADR、コンテキスト、境界づけられた、などの語を利用者に向けて使わない。ADR を書く判断は内部で行い、書いたら「決めたことを docs/adr/ に残しました」とだけ伝える。
- 事実 (既存の RAML、フロー、サンプル、コネクタ、Exchange 上の既存 API) は自分で読む。利用者に聞かない。Anypoint 側の事実は `platform-assistant` スキルと MCP `search_asset` で調べる。
- 用語集 CONTEXT.md は更新するが、利用者に確認は求めない。
- 必ず聞くべき枝: 入力の例、出力の例、失敗するケースとそのときの返し方、認証の有無、既存 API との重複。

木が尽きたら手順 3 へ。

## 手順 3. 受け入れ条件に変換し、承認をとる (人のゲート 1)

合意内容を **散文ではなく実行可能な形** にする。

- `api/<name>.raml` の差分 (新規なら全文)。
- `samples/<resource>/<case>.in.json` と `.out.json` のペア。正常 1 件、失敗 1 件以上。
- `src/test/munit/<resource>-test.xml`。samples を流して out と比較する **本物のテスト**。この時点で `mvn -q test -Dmunit.test=<resource>-test.xml` が **失敗する** ことを確認する (TDD の Red)。実装は実行ループが Green にする。
- RAML の草稿には MCP `generate_api_spec` を使ってよい。`api-spec-validator` があれば通す。既存 API との重複は MCP `search_asset` か `platform-assistant` で自分で調べる。

そのうえで利用者に **平文で動作を読み上げる**。例:
「注文番号を渡すと、SAP に問い合わせて注文の状態を返します。番号が無いときは 404 で『注文が見つかりません』を返します。この動きで合っていますか。」

承認されるまで実装に進まない。承認されたら `docs/spec/<name>.md` に読み上げた文とファイル一覧を残す。

## 手順 4. 台帳を切る (計画ループ)

`tasks/_template.md` の形式で `tasks/T-NNN.md` を作る。規則:

- 1 ゴール = 1 つの MUnit テストクラスで判定できる大きさ。縦に薄く切る (RAML → フロー → 変換 → テスト を 1 本で通す)。横に層で切らない。
- **`done_when` は必ず書く。** 通常は `mvn -q test -Dmunit.test=<テストファイル名>`。書けないゴールは粒度が間違っているので切り直す。
- `blocked_by` で依存を書く。無いものから着手できる。
- 先にやるべき下準備 (pom の依存追加、共通エラーハンドラ) があれば T-001 にする。

台帳を表にして利用者に見せる。ここは確認だけで承認は不要。

## 手順 5〜7. 実行ループを回す

`/mule-run` の手順をそのまま実行する (Skill ツールで `mule-run` を呼んでよい)。

## 手順 8. 締め

全ゴールが `passed` になったら:
1. `mule-reviewer` エージェントを起動し、`request-changes` なら指摘をゴールに変換して台帳に追加し、手順 5 へ戻る。
2. `approve` なら `/commit` 相当でコミットし、`gh pr create` で PR を作る。
3. 利用者に PR の URL と、読み上げた仕様の再掲だけを伝える。**マージは人が押す (人のゲート 2)。**
