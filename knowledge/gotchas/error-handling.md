# エラー処理 (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す。他の主題と確認した版もそこに。

## `on-error-continue` は「一番内側のスコープ」の直後から再開する
これが今回いちばん時間を溶かした。`<try>` の中でエラーが起き、既定のエラーハンドラの
`on-error-continue` が処理すると、**フロー全体が終わるのではなく `<try>` の直後から実行が続く**。
`try` の後ろに「成功時にしか意味のない変換」を置いていると、それがエラー処理の後で走り、
本来 404 を返すはずの経路が 502 になる。
仕組みは、`defaultErrorHandler-ref` の既定ハンドラが **error-handler を持たない `<try>` にも適用される** ため。try が自分で処理した扱いになり、直後から続く。
対処は簡単で、**成功時にしか意味のない処理を同じ `try` の中に入れる**。
根拠: finance-api の `change-address` で実測。`address-not-found` だけが落ちる形で現れた
(2026-09-06)。同じ罠を別のゴールで踏み直しかけたのを K-004 が食い止めている。

## 共有のエラーハンドラに `on-error-propagate` を足すと、トランザクションを持たないフローが壊れる
`<configuration defaultErrorHandler-ref="..."/>` は全フローに効く。ロールバックのために
そこへ `on-error-propagate` を追加すると、`<try>` を持たないフローでは応答を返す前に
エラーが外へ抜け、それまで通っていたテストが落ちる。
**巻き戻しが要るフローの `<try>` の中にローカルの `<error-handler>` を閉じ込める。**
根拠: finance-api で共有側に入れて `name-test.xml` が壊れることを実験で確認し、戻した (2026-09-06)。

## `<try>` の中で `<error-handler>` は最後の子要素にする
content model が `(processor)*, (error-handler)?` なので、`db:update` などより前に置くと
`mvn -q clean package -DskipTests` が XML スキーマ検証で落ちる。
根拠: finance-api で実測 (2026-09-06)。

## コネクタ組み込みのエラー型は `<raise-error>` できない
`APIKIT:BAD_REQUEST` や `DB:CONNECTIVITY` をテスト用に `raise-error` しようとしても通らない。
名前空間がアプリのものでないため。**実際にその経路を踏ませて発生させるしかない。**
`APIKIT:*` を踏ませるには実 HTTP か、型付けした attributes での `flow-ref` が要る。
根拠: finance-api で `APIKIT:BAD_REQUEST` と `DB:CONNECTIVITY` の両方で確認 (2026-09-06)。

## 独自エラー型は `raise-error` が最低 1 箇所無いとビルドが通らない
`<on-error-continue type="APP:CUSTOMER_NOT_FOUND">` と書くだけでは
`Could not find error 'APP:CUSTOMER_NOT_FOUND'` でビルドが落ちる。
実装前にハンドラだけ先に書くとき (TDD では普通に起きる) は、到達しない分岐に
`raise-error` を 1 つ置いておく。
根拠: finance-api の T-001 で実測 (2026-09-06)。

## `ANY` を接続エラーと同じ枝に入れない
`type="DB:CONNECTIVITY, DB:*, ANY"` と書くと、DataWeave の失敗やアプリの欠陥まで
「外部システムに接続できません」として報告される。**内部の欠陥が外部のせいになる。**
`ANY` は別の枝にして、内部エラー用の種別と 500 を割り当てる。
根拠: finance-api のレビュー指摘。実際にこの機構で 404 が 502 に化けていた (2026-09-06)。
