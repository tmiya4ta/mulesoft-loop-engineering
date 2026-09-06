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

## CE で失われるのはカバレッジ計測だけ (機能は動く)
`mvn test` の MUnit は既定で `MULE_CE` として走る (`Running MULE_CE with version 4.12.2`)。
しかし埋め込みコンテナには EE のモジュールが入っており、**EE 専用機能もそのまま動く**。
実測: `ee:transform` (Transform Message) も `batch:job` も CE 実行で成功する
(ログに `com.mulesoft.mule.runtime.module.batch` が出る)。
したがって CI/CD で EE 資格情報が無くても **テストの実行そのものは問題ない**。
CE で失われるのは **カバレッジ計測だけ**。Studio (EE) で通って CI (CE) で落ちる、という
食い違いは起きない。
根拠: Studio 生成 finance-api (Mule 4.12.2) で ee:transform と batch:job を CE 実行、
どちらも Tests run: 1 - Failed: 0 (2026-09-06)。

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

## Studio / ACB / CLI のどれで作っても pom に MUnit は入っていない
`dx mule project create` も Anypoint Studio も、生成直後の pom には munit-runner / munit-tools /
munit-maven-plugin が無い。Studio は MUnit テストを GUI で作った時点で初めて追加する。
CLI とループから使うときは `scripts/add-munit.sh` で明示的に足す。
根拠: Studio 生成の finance-api と CLI 生成の order-sapi の両方で確認 (2026-09-06)。

## Studio の pom はタブ字下げ、CLI はスペース字下げ
pom を機械で書き換えるスクリプトが `"    </properties>"` のようにスペース前提で置換していると、
Studio 生成の pom では **一致せず、何もせずに成功したように見える**。字下げは正規表現で受け、
書き込み前に「入ったか」を検証して入っていなければ落とすこと。
根拠: add-munit.sh が Studio プロジェクトで無言の no-op になった (2026-09-06)。

## Mule 4.12 に MUnit 3.4 系を載せると起動しない
`java.lang.module.ResolutionException: Modules org.codehaus.plexus.util and plexus.utils export
package org.codehaus.plexus.util.cli to module json.schema.validator` が出て
`Cannot create embedded container` で全テストが落ちる。テストの失敗と区別がつきにくい。
MUnit 3.7.4 で解消する。版を固定せず maven-metadata の `<release>` を見て最新を使う。
根拠: Studio 生成 (Mule 4.12.2) で 3.4.0 が起動失敗、3.7.4 で Red/Green 成立 (2026-09-06)。

## コネクタの GAV を推測しない
実在しない版を `--dependencies` に書くと `mvn` が「not found」で落ち、自力では直せない。
`anypoint-cli-v4 dx mule describe-connector` か Exchange で確認する。
根拠: 公式スキル build-mule-integration の Step 8 が同じ警告をしている。

## DataWeave の検査は `dw validate -f`。`dw -f` は存在しない
dw CLI (Command Line V1.0.34) に単体の `-f` は無く、**正しい .dwl でも exit 2** を返す。
段 1 が全ての .dwl 編集を無条件に弾き、実行ループが進まなくなる。
さらに `dw validate` は Mule の dwl に 2 つの誤判定を出す。

| 誤判定 | なぜ Mule では正常か |
|---|---|
| `Missing Mapping Expression` | 変換を module (`---` を持たないファイル) に切り出すのは規則 5 が求める形 |
| `Unable to resolve reference of: payload` | `payload` `vars` `attributes` は実行時にしかない束縛 |

**module の本物の構文エラーは正しく捕まる** (`fun f(x) = x +` → `Missing addition expression`) ので、
この 2 つを除いた残りの `[ERROR]` だけを見れば検証器として使える。ANSI の色コードが混じるので
grep の前に落とす。`scripts/quick-check.sh` は修正済み。
根拠: System API 1 本の実装中に 2 段階で露見 (2026-09-06)。1 つ目は最初の .dwl 編集で即座に、
2 つ目は変換を module に切り出した直後に。module 正常 / module 壊れ / payload 参照 /
script 壊れ / 素の正常 / 素の壊れ / 実物 2 本の 8 通りで期待どおりを確認。

## `ee:` を 1 つでも書くと MUnit が動かない (CE 環境)
`<ee:transform>` を 1 つ置くと `target/META-INF/mule-artifact/mule-artifact.json` の
`requiredProduct` が `MULE` → `MULE_EE` に変わり、MUnit が EE の器を作ろうとする。
`com.mulesoft.mule.distributions:mule-runtime-impl-no-services-bom:4.9.0` は公開リポジトリに
**無い** (404。4.10.1 は 200) ので `Cannot create embedded container` で落ちる。
`<runtimeProduct>MULE_EE</runtimeProduct>` を書いた場合と同じ症状だが、**原因は名前空間 1 つ**で、
pom には何も書いていないので気づきにくい。

変換は `src/main/resources/dwl/` の module に置き、フローからは `#[dwl::Module::fn(...)]` の
1 行で呼ぶ。規則 5 が求める形と一致するので、迂回ではなく本来の形に寄る。
根拠: 3 つの worktree が独立に同じ壁に当たり、進捗エージェントが対照実験で確認 (2026-09-06)。
`ee:transform` あり → `requiredProduct: MULE_EE` / exit 1、退避 → `MULE` / exit 0。

## `mock-when` は操作に付けた `error-mapping` ごと無効化する
`<munit-tools:mock-when>` は操作そのものを差し替えるので、その操作に付けた
`<error-mapping sourceType="..." targetType="..."/>` は効かない。
mock 経由ではエラー型が写し替わらず、テストだけが赤くなる。
エラー型の写し替えは操作の外 (`<try>` + `on-error-propagate`) に出す。
なお `error-mapping` は XSD 上 `db:sql` より前に置く必要があり、順を間違えると
配備前に `cvc-complex-type.2.4.a` で落ちる。
根拠: 一意制約違反を 409 に写す実装中に 2 段で露見 (2026-09-06)。
