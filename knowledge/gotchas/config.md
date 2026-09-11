# 設定とプロパティ (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

## ローカル実行で `${x.y}` を上書きできるのはシステムプロパティだけ (環境変数は読まれない)
`mvn test -Dcif.db.user=X` は効く。`env cif.db.user=X mvn test` も `env CIF_DB_USER=X mvn test` も効かない
(configuration-properties は起動時に OS 環境変数を見ない)。CH2 / RTF では Runtime Manager の Properties が
コンテナ内でシステムプロパティに反映されるので効く (こちらは未検証の推測)。
根拠: finance-api T-009 / T-012 で 4 パターンを実測 (2026-09-07)。

## 数値として解釈されるプロパティ (`port` など) に `SET_...` を置くと、MUnit が起動しない

**症状 (原文)**:
```
org.mule.runtime.ast.api.ParameterResolutionException: Exception resolving param 'port' with
value 'SET_INVENTORY_DB_PORT' at 'global.xml:...' (java.lang.NumberFormatException: For input
string: "SET_INVENTORY_DB_PORT")
```

**原因**: `db:oracle-connection` のようなベンダ専用の接続要素は `port` を**数値の属性**として持つ。
設定ファイルの既定値を `SET_...` (実値は配備先で入れる、の意味の置き字) にすると、
**MUnit の起動時に**数値へ変換しようとして落ちる。MUnit は DB 操作を mock するのに、
接続設定の解決は起動時に走るため。`db:generic-connection` (URL 全体を文字列で渡す) では起きない。

**直し方**: 数値として解釈される項目の既定値だけは**数値として読める文字列**にする (例: `"0"`)。
host / user / password は `SET_...` のままでよい (どうせ接続自体が失敗し、認証まで到達しない)。

根拠: inventory3-api T-001 で実測 (2026-09-11)。

## YAML の configuration-properties の値はすべて文字列になる
`config.yaml` の `blockSize: 100` も文字列として届く。batch の `blockSize` / `maxConcurrency` のように数値が要る属性は YAML でクォートしない。
`<global-property name="mule.env" value="local"/>` は `<configuration-properties>` より前に置く。`${mule.env:local}` の既定値付き参照は RTF で解決に失敗することがある。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## `p()` は `configuration-properties` の YAML のネストしたキーを動的に引ける
`p('messages.' ++ fieldName)` の形が効く。エラーハンドラの中で `readUrl` を使うと、
読み込み失敗が「エラーハンドラの中の 2 つ目のエラー」になり、
**problem+json を名乗りながら中身が違う応答**を返す道ができる。起動時解決に寄せる。
根拠: finance-api の T-005 で実測 (2026-09-06)。
