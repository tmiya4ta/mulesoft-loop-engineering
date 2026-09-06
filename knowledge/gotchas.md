# 共有ナレッジ (全リポジトリに効く)

実行エージェントとレビューエージェントが毎回読む。`/mule-learn --share` の PR で増える。
**根拠のない項目を足さない。** 各項目に「何回どこで起きたか」を必ず書く。

---

## MUnit の絞り込みは `-Dmunit.test=`
`-Dtest=` は surefire 用で MUnit には効かない。ファイル名を渡す。
`mvn -q clean test -Dmunit.test=order-cancel-test.xml`
根拠: プラグイン開発時の検証 (2026-09-05)。

## `done_when` には必ず `clean` を付ける
`clean` 無しで入力に変化が無いと Maven が `Skipping execution of munit because it has already been run` で
テストを実行せず BUILD SUCCESS を返す。判定が空振りする。
根拠: プラグイン開発時の検証 (2026-09-05)。

## MUnit のカバレッジ計測は Enterprise 限定
`requiredApplicationCoverage` を設定しても、CE ランタイムでは
`WARNING Coverage is a EE only feature and you've selected to run over CE` が出るだけで素通りする。
設定してあること自体が「効いている」証拠にならない。EE が無い環境では
`scripts/coverage-check.sh` の構造チェック (全 flow が MUnit から flow-ref される) が唯一の保証。
**この構造チェックは flow への到達だけを見る。** `choice` の分岐、`try` の失敗経路、`error-handler` の
各 error-type は見えないので、100% と出ても分岐が通っていないことがある。分岐は samples のケースで数える。
`<runtimeProduct>MULE_EE</runtimeProduct>` を EE の認証なしに書くと、逆に全テストが
`Cannot create embedded container` で落ちる。
根拠: プラグイン開発時の検証 (2026-09-05)。

## 手書き pom はライブラリ取得に失敗する
`mule-maven-plugin` の `<extensions>true</extensions>`、`mule-application` パッケージング、
Exchange / MuleSoft のリポジトリ定義、`mule-artifact.json` のどれかが欠ける。
必ず `anypoint-cli-v4 dx mule project create` か MCP `create_mule_project` で骨格を作る。
根拠: 利用者からの指摘 + 検証 (2026-09-05)。

## `dx mule project create` の生成物に MUnit は入っていない
`scripts/add-munit.sh` で munit-runner / munit-tools / munit-maven-plugin を足す。
`--skip-environment` は CLI 1.0.3 には存在しない (公式スキルの記述は古い)。
根拠: 検証 (2026-09-05)。

## コネクタの GAV を推測しない
実在しない版を `--dependencies` に書くと `mvn` が「not found」で落ち、自力では直せない。
`anypoint-cli-v4 dx mule describe-connector` か Exchange で確認する。
根拠: 公式スキル build-mule-integration の Step 8 が同じ警告をしている。
