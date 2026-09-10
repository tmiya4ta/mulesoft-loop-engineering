---
name: mule-munit
description: MUnit を書くときに毎回踏んでいる罠だけを、踏む順に並べたチェックリスト。mock-when 漏れ、カバレッジ、牙の無い assert、APIkit の振り分け flow の直叩き。MUnit を書く・直す・カバレッジが通らない・テストが緑なのに信用できないときに使う。
---

台帳 (`knowledge/failures.jsonl` 62 件) のうち **18 件が MUnit とテスト** で、主題としては最大です
(`munit-coverage` 8 + `munit-mock-missing` 4 + `test-toothless` 6)。
中身は `mock-when` 漏れ、カバレッジ未達、そして**牙の無い assert**。どれも書き方の癖で防げます。

**このファイルは Mule や MUnit の入門ではありません。** 基礎は `knowledge/basics/munit.md`、
Red → Green → Refactor の順は `mule-tdd`、根拠と日付つきの詳細は `knowledge/gotchas/munit.md` (12 件) にあります。
**この 2 ファイルだけで足ります。`knowledge/gotchas.md` / `mule-basics.md` は索引なので、丸ごと読まない。**
ここに置くのは**順番と写経元の在処**だけです。

> パスの解決: 実行エージェントは Skill ツールを持たないので、
> `bash scripts/plugin-root.sh --skill mule-munit` / `bash scripts/plugin-root.sh <相対パス>` で
> 絶対パスに直してから Read します。

## 書く前に 30 秒で確かめる 5 つ

| # | 確認 | 外すとどうなる |
|---|---|---|
| 1 | 実処理 flow (HTTP を知らない flow) を叩いているか | 振り分け flow / main flow を叩くなら attributes の型付けが要る (下の「APIkit」) |
| 2 | 外部操作を**全部** `mock-when` したか。`processor` + `doc:name` で特定する | 実 DB / 実 HTTP に行く。`HTTP:CONNECTIVITY ... Connection refused` |
| 3 | モックしたい操作に `target=` が付いていないか | **`target=` があるとモック値が変数に入らない。** 実装側で `target` を外して `payload` を使う |
| 4 | assert の式に `default` が無いか | 未設定でも通る。**何も検証していない** |
| 5 | 期待値を samples から `readUrl` で読んでいるか | 手で書き写すと実装を直しても検査が気付かない |

## 要素名・操作名・パラメータ名は推測しない

`reference/mule-schema/INDEX.md` (`scripts/schema-index.sh` が `~/.m2` の jar から生成、版が一致)
から引きます。`munit-tools.xml` に `mockWhen` / `assertThat` / `verifyCall` の定義、
各コネクタの `.xml` に操作の定義があります。**推測して書いた XML は名前空間エラーで落ちるだけ**なので、
先に引く方が速い。

## コネクタの戻り値の形は操作ごとに違う

`then-return` に何を返すかを間違えると、実装は正しいのにテストだけ落ちます。
`db:select` は配列、`db:update` は `{affectedRows}`。列名は DB が返す形 (大文字など) に合わせる。
コネクタのエラーは `<munit-tools:error typeId="DB:CONNECTIVITY"/>` で起こす
(コネクタ組み込みのエラー型は `<raise-error>` できない)。詳細は `knowledge/basics/db.md` と `knowledge/gotchas/db.md`。

## APIkit の振り分け flow を叩く (**ここで 6 回踏んでいる**)

`<method>:\<path>[:<mediaType>]:<config 名>` という名前の受け口 flow は `attributes.uriParams` を
読むので、**attributes を型付けして渡さないと動きません**。写経元がこれです:

```
${CLAUDE_PLUGIN_ROOT}/template/reference/router-test.xml
```

3 つの型を間違えると動きません。`headers` / `queryParams` は `MultiMap`、`uriParams` は
`java.util.HashMap`、全体は `HttpRequestAttributes`。

**やってはいけない代替**: attributes 無しで `flow-ref` すると NPE で `global-error-handler` の
`ANY` 枝 (500) に落ちるので、`vars.httpStatus` が non-null であることだけを assert すれば
カバレッジは通ります。**通りますが、リクエスト内容による分岐を何も検証していません。**
inventory2-api にこの形のテストが 7 本残り、`test-toothless` として台帳に上がりました。
型付けすれば同じ手間で正常応答の中身まで assert できます。

**検索系の例外**: `queryParams` が全て任意項目の振り分け flow では、attributes 無しでも
DataWeave の null 伝播でエラーにならず**正常完走してしまう**ので、上の「500 に落ちる」前提の
やり方はそもそも成り立ちません (`router-test.xml` の 3 つ目の例)。

**承認済みの `<resource>-test.xml` は変更しません。** 振り分け flow のカバレッジは
`<resource>-router-test.xml` として別ファイルに分けます (受け入れ条件のファイルを触らないため)。

## カバレッジ

判定は `bash scripts/coverage-check.sh` (exit 0)。見ているのは
**「追加した flow / sub-flow がどれかの `munit:test` から `flow-ref` されたか」だけ**です。

`choice` の各分岐、`try` の成功と失敗、`error-handler` の各 error-type は**見ていません**。
そこは samples のケースを増やして 1 つずつ通す。機械が保証しないので、書く側が数えます。

- **`http:listener` を持つ flow を叩くとき**は `<munit:enable-flow-sources>` で明示的に有効化する
  (MUnit は既定でメッセージソースを起動しない)。
- **エラー型の登録用スタブ** (`flow-ref` されない `sub-flow`) は、変数未指定なら no-op で戻るようにして
  専用の MUnit から安全に `flow-ref` する。
- 本物のカバレッジ率計測は EE 限定。`scripts/munit-coverage-mode.sh` が EE を取れるときだけ pom に
  100% ゲートを入れ、取れなければこの構造チェックが唯一の保証になります。

## 実装を直したら、既存テストの `behavior` を見直す

早期終了していた分岐が後続処理に到達するようになると、モック不足で実 DB へ行き
404 が 502 に化けます。**足すのは `behavior` だけ。`assert` は変えません。**

## 書いたテストに牙があるか確かめる

緑は「通った」であって「検証した」ではありません。台帳の `test-toothless` 6 件のうち **5 件が
「検査自体が一度も走っていなかった」**で、そのうち 3 件は**牙の確認そのものが当たっていなかった**もの
でした。**だから手で細工して目で見るのはやめます。** 機械に測らせます:

```bash
bash scripts/teeth-check.sh --file src/test/munit/<resource>-test.xml \
     --old '<壊す前の文字列>' --new '<壊した後の文字列>' --case <case 名>
```

**期待値そのものを壊します** — `readUrl` の参照先を別の sample に差し替える、`equalTo` の値を変える、
読む変数名を存在しないものにする。`doc:name` のような assert が読まない箇所を壊しても落ちません
(それを「牙が無い」と読み違えます)。

exit 0 なら牙あり。exit 2 のときは**理由が 5 つに分かれて出る**ので、そのまま読んでください:

| 出た理由 | 意味 |
|---|---|
| 当て先が 0 箇所 / 2 箇所以上 | 細工が当たらない。**行番号では指定しません** (行がずれて 1 文字も当たらなかった実例があります) |
| case が見つからない | 名前の打ち間違い。`mvn` を 2 回回す前に止まります |
| 細工前が緑ではない | 赤いまま細工しても、赤い理由が細工とは限りません |
| 細工しても 1 件も落ちない | **このテストに牙がありません。** 壊した箇所を assert が読んでいません |
| 落ちたのが別の case | **exit が非ゼロになったことを牙の証拠にしない。** 前処理が先に落ちている形が実際にありました |

対象ファイルは**必ず元に戻ります** (異常終了でも戻します)。

## MUnit で検証できないもの (緑でも保証されていない)

- **トランザクションの commit / rollback。** `mock-when` は processor ごと差し替えるので JDBC に
  到達しません。検証できるのは「巻き戻しの経路を通ったこと」まで。
- **SQL 文そのもの**と **listener の直列化**。

これらは限界として K ファイルに明記し、`samples/` と `/mule-deploy` の smoke-check に委ねます。

## 禁止

- テストや `samples/` の期待値を実装に合わせて変えること。間違っていると確信したら**止まって**報告する。
- `mock-when` を使わず実際の外部システムに繋ぐこと。
- assert の式に `default` を付けること。
- カバレッジを通すためだけの、応答の中身を見ないテストを足すこと。
