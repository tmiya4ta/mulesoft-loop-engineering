# MUnit (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

## MUnit の絞り込みは `-Dmunit.test=`
`-Dtest=` は surefire 用で MUnit には効かない。ファイル名を渡す。
`mvn -q clean test -Dmunit.test=order-cancel-test.xml`
根拠: プラグイン開発時の検証 (2026-09-05)。

## `done_when` には必ず `clean` を付ける
`clean` 無しで入力に変化が無いと Maven が `Skipping execution of munit because it has already been run` で
テストを実行せず BUILD SUCCESS を返す。判定が空振りする。
根拠: プラグイン開発時の検証 (2026-09-05)。

## CE で失われるのはカバレッジ計測だけ (EE 機能は動く。計測は素通り)
`mvn test` の MUnit は既定で `MULE_CE` として走る (`Running MULE_CE with version 4.12.2`)。
しかし埋め込みコンテナには EE のモジュールが入っており、**EE 専用機能もそのまま動く**。
実測: `ee:transform` も `batch:job` も CE 実行で成功する (ログに `com.mulesoft.mule.runtime.module.batch` が出る)。
CI/CD で EE 資格情報が無くても **テストの実行そのものは問題ない**。Studio (EE) で通って CI (CE) で落ちる、という食い違いは起きない。

失われるのは **カバレッジ計測だけ**。`requiredApplicationCoverage` を設定しても CE では
`WARNING Coverage is a EE only feature and you've selected to run over CE` が出るだけで素通りする。
設定してあること自体が「効いている」証拠にならない。EE が無い環境では `scripts/coverage-check.sh` の
構造チェック (全 flow が MUnit から flow-ref される) が唯一の保証。**この構造チェックは flow への到達だけを見る。**
`choice` の分岐、`try` の失敗経路、`error-handler` の各 error-type は見えないので、100% と出ても分岐が通っていないことがある。分岐は samples のケースで数える。
`<runtimeProduct>MULE_EE</runtimeProduct>` を EE の認証なしに書くと、逆に全テストが `Cannot create embedded container` で落ちる。
根拠: プラグイン開発時の検証 (2026-09-05)、Studio 生成 finance-api (Mule 4.12.2) で ee:transform と batch:job を CE 実行 (2026-09-06)。

## `mock-when` は操作に付けた `error-mapping` ごと無効化する
`<munit-tools:mock-when>` は操作そのものを差し替えるので、その操作に付けた
`<error-mapping sourceType="..." targetType="..."/>` は効かない。
mock 経由ではエラー型が写し替わらず、テストだけが赤くなる。
エラー型の写し替えは操作の外 (`<try>` + `on-error-propagate`) に出す。
なお `error-mapping` は XSD 上 `db:sql` より前に置く必要があり、順を間違えると
配備前に `cvc-complex-type.2.4.a` で落ちる。
根拠: 一意制約違反を 409 に写す実装中に 2 段で露見 (2026-09-06)。

## MUnit は SQL 文も listener の直列化も検証しない
`munit-tools:mock-when` は DB の操作ごと差し替えるので、**`db:sql` の中身は
文字列として組み立てられるだけで一度も実行されない。** 表名やスキーマ修飾を
間違えても全件緑のまま通る。

listener も同じで、MUnit の器と配備先で Mule の版が違うと応答の形が変わる。

実例: System API 1 本で 2 回起きた。34 件緑・レビュー approve のまま、
(1) スキーマ修飾の誤りで配備先の全操作が 500、
(2) 直したあとも全応答が JSON 文字列に二重に包まれていた。
どちらも配備して手で叩くまで気づかなかった。

対策は `docs/methodology.md` の **段 4 (配備先への契約検査)**。
`samples/` をそのまま流す。期待値を別形式に書き写すと二重管理になり必ずずれる。
根拠: System API 1 本の実装で 2 件とも実測 (2026-09-06)。

## MUnit は既定でメッセージソース (http:listener) を起動しない
配線が正しくても、実 HTTP を叩くテストが毎回 `HTTP:CONNECTIVITY ... Connection refused` になる。
`mvn -q clean package -DskipTests` は成功するので設定ミスに見えるが違う。
`<munit:enable-flow-sources>` で対象の flow を明示的に有効化する。
根拠: finance-api の T-001 で実測 (2026-09-06)。

## APIkit が生成する flow を `flow-ref` で直叩きするには attributes を型付けする
**main flow だけでなく、APIkit の振り分け flow (`<method>:\<path>[:<mediaType>]:<config name>` という
名前の、リソースごとの受け口 flow) にも同じ問題が起きる。** `apikit:router` は attributes を
`org.mule.extension.http.api.HttpRequestAttributes` として扱う。ただの Map を渡すと動かない。
DataWeave で `... as Object {class: "org.mule.extension.http.api.HttpRequestAttributes"}` と型付けする。
`headers` と `queryParams` は `org.mule.runtime.api.util.MultiMap` にする。
カバレッジ検査がこれらの flow の `flow-ref` を要求するときに必要になる。型付けせずに `flow-ref` すると
`attributes` が無いために `vars` の算出で NPE / 型エラーになり、`global-error-handler` の `ANY` 枝 (500)
に落ちる — それを「利用」して `httpStatus` が non-null であることだけを assert する手もあるが、
実際のリクエスト内容による分岐を何も検証しない牙の弱いテストになる (`test-toothless` と同じ構造)。
型付けして正常応答の中身まで assert する方が同じ手間で堅い。
写経元は `template/reference/router-test.xml` (パス変数あり / 本文あり / 検索系の 3 形)。
根拠: finance-api の T-001 (main flow) で組み立てて成功 (2026-09-06)。inventory2-api で振り分け flow
側の同じ問題を 6 回再発 (T-002〜T-006、見出しが `main flow` に限定されていたため「別問題」と
判断されて型付けせず、上記の弱いテストで代替していた。2026-09-09)。**振り分け flow に対する型付けを
実測で確認 (2026-09-10)**: `get:\inventory\(inventoryId):inventory2-api-config` を型付け attributes で
叩いて `payload.inventoryId` / `payload.warehouseCode` まで assert し 1 件 pass、期待値を壊すと
Failed: 1 / exit 1 (牙も確認)。**弱いテストで代替する必要は無い。**

## queryParams が全て任意項目だと、attributes 無しの `flow-ref` が正常完走してしまう
上の項目の「attributes 無しで NPE / 型エラーになり ANY(500) に落ちる」ことを前提にした確認は、
振り分け flow のパラメータが**全て任意項目** (RAML の queryParams が `?` 付きのみ) のときは成り立たない。
`attributes` が無くても DataWeave の null 伝播でエラーにならず、flow がそのまま正常完走する。
検索系 (一覧・検索 API) の振り分け flow で起きやすい。attributes を型付けするのが本筋の対処だが、
それをしない場合は「500 に落ちることを前提にした assert」ではなく「既定値 (limit/offset の default 等)
で正常応答が返ることを assert する」形にする必要がある。
根拠: inventory2-api の T-003 で実測 (2026-09-09)。

## db 操作に `target=` を付けると `mock-when` の値が反映されない
`target="result"` のように結果を変数へ入れる書き方をすると、モックした値がその変数に入らず、
後続の分岐が実 DB へ行こうとする。`target` を外して `payload` を直接参照すると解消する。
原因までは特定していない。症状と対処のみ。
根拠: finance-api の T-003 で実測 (2026-09-06)。

## トランザクションの commit / rollback は MUnit では観測できない
`mock-when` は processor ごと差し替えるため、JDBC のコネクション取得もトランザクション参加も
発生しない。検証できるのは「巻き戻しの経路を通ったこと」までで、実際に戻ったかではない。
**テストが緑でも、そこは保証されていない。**限界を明記して残すこと。
根拠: finance-api の T-005 で確認 (2026-09-06)。

## フローの分岐を変えたら、既存テストの `behavior` にモックを足す
早期終了していた分岐が新しい実装では後続処理に到達し、モック不足で実 DB へ行って
404 が 502 になる。**`assert` は変えない。足すのは `behavior` だけ。**
根拠: finance-api の T-006 で実測 (2026-09-06)。

## `assert` の式に `default` を付けると、そのテストは何も検証しない
```xml
expression="#[vars.updatedRows default 1]"  is="#[MunitTools::equalTo(1)]"
```
変数が未設定でも通る。`doc:name` が何を主張していても、検証はされていない。
**検出方法**: 参照している変数名を存在しないものに差し替えて、テストが通るかを見る。
通ったら牙が無い。`verify-call` で実際に発行された呼び出しと引数を見る形に置き換える。
根拠: finance-api でレビューが発見。変数名の差し替えで実際に素通りすることを確認 (2026-09-06)。
