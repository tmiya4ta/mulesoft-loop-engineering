# 設定とプロパティ (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す。他の主題と確認した版もそこに。

## ローカル実行で `${x.y}` を上書きできるのはシステムプロパティだけ (環境変数は読まれない)
`mvn test -Dcif.db.user=X` は効く。`env cif.db.user=X mvn test` も `env CIF_DB_USER=X mvn test` も効かない
(configuration-properties は起動時に OS 環境変数を見ない)。CH2 / RTF では Runtime Manager の Properties が
コンテナ内でシステムプロパティに反映されるので効く (こちらは未検証の推測)。
根拠: finance-api T-009 / T-012 で 4 パターンを実測 (2026-09-07)。

## YAML の configuration-properties の値はすべて文字列になる
`config.yaml` の `blockSize: 100` も文字列として届く。batch の `blockSize` / `maxConcurrency` のように数値が要る属性は YAML でクォートしない。
`<global-property name="mule.env" value="local"/>` は `<configuration-properties>` より前に置く。`${mule.env:local}` の既定値付き参照は RTF で解決に失敗することがある。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## `p()` は `configuration-properties` の YAML のネストしたキーを動的に引ける
`p('messages.' ++ fieldName)` の形が効く。エラーハンドラの中で `readUrl` を使うと、
読み込み失敗が「エラーハンドラの中の 2 つ目のエラー」になり、
**problem+json を名乗りながら中身が違う応答**を返す道ができる。起動時解決に寄せる。
根拠: finance-api の T-005 で実測 (2026-09-06)。
