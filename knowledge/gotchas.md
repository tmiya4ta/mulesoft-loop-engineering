# 共有ナレッジ (全リポジトリに効く)

実行エージェントとレビューエージェントが毎回読む。`/mule-learn --share` の PR で増える。
**根拠のない項目を足さない。** 各項目に「何回どこで起きたか」を必ず書く。
主題別に並べてある。**知っていれば試さなくて済むこと**の要約は `knowledge/mule-basics.md`。こちらは症状の原文と根拠を持つ側。

**プラットフォーム操作 (API Manager、ポリシー、Exchange) は手探りの前に同梱の公式スキルを読む。**
`secure-api`、`apply-policy-to-api-instance`、`platform-assistant`。実例で遠回りした落とし穴のうち 3 件は既にそこに書いてあった (PR #2、2026-09-06)。

確認した版 (2026-09-05〜07): Mule 4.12.2 / MUnit 3.7.4 / APIkit 1.12.6 / mule-db-connector 1.16.3 /
mule-http-connector 1.10.0 / mule-maven-plugin 4.10.1 / Java 17 / CE。

## 目次
- プロジェクトとビルド (10)
- 設定とプロパティ (3)
- MUnit (12)
- エラー処理 (6)
- APIkit と HTTP (3)
- DB コネクタ (6)
- DataWeave (3)
- 配備 (CloudHub 2.0 / Runtime Fabric) (6)
- API Manager とポリシー (4)

---

# プロジェクトとビルド

## 手書き pom はライブラリ取得に失敗する
`mule-maven-plugin` の `<extensions>true</extensions>`、`mule-application` パッケージング、
Exchange / MuleSoft のリポジトリ定義、`mule-artifact.json` のどれかが欠ける。
必ず `anypoint-cli-v4 dx mule project create` か MCP `create_mule_project` で骨格を作る。
根拠: 利用者からの指摘 + 検証 (2026-09-05)。

## Studio / ACB / CLI のどれで作っても pom に MUnit は入っていない
`dx mule project create` も Anypoint Studio も、生成直後の pom には munit-runner / munit-tools /
munit-maven-plugin が無い。Studio は MUnit テストを GUI で作った時点で初めて追加する。
CLI とループから使うときは `scripts/add-munit.sh` で明示的に足す。
`--skip-environment` は CLI 1.0.3 には存在しない (公式スキルの記述は古い)。
根拠: CLI 生成の order-sapi (2026-09-05)、Studio 生成の finance-api (2026-09-06) の両方で確認。

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

## `dx mule project create` は mule-maven-plugin 4.7.0 を固定する (4.12 系と非互換)
`--mule-version 4.12.2` を指定しても pom の `mule.maven.plugin.version` は 4.7.0 のままで、
`java.lang.NoSuchMethodError: 'boolean org.mule.runtime.features.api.MuleRuntimeFeature.isEnabled(java.util.Optional)'`
が出て `process-classes` で落ちる。Studio が生成する pom は 4.10.1 なのでこの問題は起きない。
`scripts/fix-plugin-version.sh` が app.runtime を見て 4.10 系に上げる。
根拠: CLI 生成 4.12.2 で 4.7.0 は exit 1、4.10.1 に上げると `ee:transform` 込みで
Tests run: 1 - Failed: 0 (2026-09-06)。

## コネクタの GAV を推測しない
実在しない版を `--dependencies` に書くと `mvn` が「not found」で落ち、自力では直せない。
`anypoint-cli-v4 dx mule describe-connector` か Exchange で確認する。
根拠: 公式スキル build-mule-integration の Step 8 が同じ警告をしている。

## `ee:` を書くと requiredProduct が MULE_EE になる。落ちるかは Mule の版で決まる
`<ee:transform>` を 1 つ置くと `target/META-INF/mule-artifact/mule-artifact.json` の
`requiredProduct` が `MULE` → `MULE_EE` に変わり、MUnit が EE の器を作ろうとする。
その解決に `com.mulesoft.mule.distributions:mule-runtime-impl-no-services-bom:<版>` が要る。

| Mule 版 | BOM の公開 | `ee:` ありの MUnit |
|---|---|---|
| 4.9.0 | **404** | `Cannot create embedded container` で落ちる |
| 4.10.1 | 200 | 動く |
| 4.12.2 | 200 | 動く (Studio 生成で実測 exit 0) |

**第一の対処は `ee:` を避けることではなく、BOM が公開されている版 (4.10.1 以降、既定は 4.12.2)
を使うこと。** `ee:transform` は Studio が既定で生成する標準部品なので、これを禁じると
利用者に重い制約を課すことになる。4.9.0 のまま進むしかない場合だけ、変換を
`src/main/resources/dwl/` の module に置き、フローからは `#[dwl::Module::fn(...)]` の 1 行で呼ぶ
(これは規則 5 が求める形と一致するので、迂回ではなく本来の形に寄る)。

症状は `<runtimeProduct>MULE_EE</runtimeProduct>` を書いた場合と同じだが、**原因は名前空間 1 つ**で
pom には何も書いていないので気づきにくい。
根拠: 4.9.0 で 3 つの worktree が独立に同じ壁に当たり対照実験で確認 (`ee:` あり → `MULE_EE` /
exit 1、退避 → `MULE` / exit 0)。4.12.2 では `requiredProduct: MULE_EE` のまま MUnit が
Tests run: 1 - Failed: 0 で通ることを確認。BOM は 4.9.0 が 404、4.10.1 と 4.12.2 が 200 (2026-09-06)。

## Maven の 401 は EE リポジトリの認証欠けか `.classpath` の EE コネクタ参照
`~/.m2/settings.xml` には Maven Central と `anypoint-exchange-v3` (Connected App: user `~~~Client~~~`、password `<client_id>~?~<client_secret>`) が要る。
`mulesoft-ee-releases` は Nexus の資格情報が無ければコメントアウト。Studio で一度足して消したコネクタの参照が `.classpath` に残ると
`com.mulesoft.connectors` の解決で 401 になる。キャッシュは `find ~/.m2/repository -name "*.lastUpdated" -delete` で捨てて `-U`。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## `javac` と `java` が別の JDK を指す環境がある
`javac` が GraalVM 25、`java` が OpenJDK 17 を指していると、コンパイルは通るのに実行で
`UnsupportedClassVersionError (class file version 69.0 ... up to 61.0)` になる。
スクリプトから呼ぶときは `readlink -f $(command -v java)` の隣の `javac` を使う。Mule 4.6 以降は Java 17。Java 25 は `java.lang.Compiler` が無く Mule / MUnit が動かない。
根拠: finance-api T-009 で実測 (2026-09-07)。Java 25 非対応は mulesoft-app-development スキル。

## リポジトリ直下の `api/*.raml` はクラスパスに乗らない
`InitialisationException: Raml not found at: api/finance-api.raml` になる。
`src/main/resources` の外にあるので当然だが、APIkit の `api=` の書き方だけを見ていると気づけない。
pom の `<resources>` に直下の `api/` を足す。
根拠: finance-api の T-001 で実測 (2026-09-06)。


---

# 設定とプロパティ

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


---

# MUnit

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
根拠: finance-api の T-001 (main flow) で組み立てて成功 (2026-09-06)。inventory2-api で振り分け flow
側の同じ問題を 6 回再発 (T-002〜T-006、見出しが `main flow` に限定されていたため「別問題」と
判断されて型付けせず、上記の弱いテストで代替していた。2026-09-09)。

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


---

# エラー処理

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


---

# APIkit と HTTP

## `attributes.requestPath` は listener のベースパス込みで返る
listener が `/api/*` なら `"/api/customers/CUST00013/address"` のようになる。
RFC 7807 の `instance` に使うと、RAML のリソースパスと食い違う。
根拠: finance-api で実測 (2026-09-06)。

## `http:request` の応答を `payload as String` すると `Cannot coerce Object to String`
応答の MIME が JSON 系だと DataWeave が自動で解釈するため、`payload` は String ではない。
テスト側で本文を文字列として扱いたいときは `http:request` に
`outputMimeType="application/java"` を付ける。`text/plain` や `application/octet-stream` では直らない。
根拠: finance-api の T-001 で 3 通り試して確認 (2026-09-06)。

## APIkit の検証エラーの `error.description` は `/<プロパティ名> ...` で始まる
```
/postalCode string [1000001] does not match pattern ^[0-9]{3}-[0-9]{4}$
```
複数の項目が同時に落ちると改行で連結される。項目名を取り出して日本語の文言表を引く、
という組み立てができる。`APIKIT:NOT_ACCEPTABLE` / `UNSUPPORTED_MEDIA_TYPE` はこの形にならないので、
既定文へのフォールバックを必ず用意する。
根拠: finance-api の T-004 で原文を採取 (2026-09-06)。


---

# DB コネクタ

## `db:update` / `db:select` の SQL は属性ではなく子要素
`sql="..."` の属性で書くと XSD 検証で落ちる。`<db:sql>...</db:sql>` の子要素にする。
根拠: mule-db-connector 1.16.3、finance-api の T-003 で実測 (2026-09-06)。

## `db:update` は UPDATE / MERGE / TRUNCATE 専用。INSERT と DELETE は別オペレーション
`<db:update>` に INSERT 文を書くと DB に届く前に Mule 側で弾かれる:
`DB:BAD_SQL_SYNTAX: Query type must be one of [UPDATE, TRUNCATE, MERGE, STORE_PROCEDURE_CALL] but query '...' is of type 'INSERT'`。
INSERT は `<db:insert>`、DELETE は `<db:delete>`。MERGE (upsert) は `db:update` で書く (`db:insert` / `db:execute-script` は `input-parameters` が使えない)。
根拠: finance-api T-010 で実測 (mule-db-connector 1.16.3、2026-09-07)。MERGE は mulesoft-app-development スキル。

## DB コネクタの戻り値の形は操作ごとに違う
| 操作 | payload | 0 件のとき |
|---|---|---|
| `db:select` | 行の配列 (`[{COL: v, ...}]`) | `[]` (`null` ではない) |
| `db:update` / `db:insert` | `{affectedRows: N, generatedKeys: {...}}` のオブジェクト (配列に包まれない) | `affectedRows: 0` |
| `db:delete` | 素の整数 (`1`) | `0` |

TIMESTAMP 列は Mule に入った時点で DataWeave の `String` (`2026-09-05T16:47:13.033`、TZ 無し)。`as String` は恒等変換。
`isEmpty(payload)` は `null` でも `[]` でも真なので、0 件判定にはこれを使う。
根拠: finance-api T-010 で実 Derby に対して 5 操作を実測 (2026-09-07)。

## `affectedRows` の意味は DB 製品で違う (Derby は一致行数、MySQL は変更行数)
Derby は WHERE に一致した行数を返す (値を変えない UPDATE でも 1)。MySQL の既定は値が変わった行数を返す (同じ値の UPDATE は 0)。
`affectedRows == 0` を「対象が存在しない」と読むと、MySQL では同じ値の PUT が 404 になり冪等性が壊れる。
**存在判定は更新後の `db:select` の読み戻しで行う。** 接続先が未確定のまま書くときはとくに。
根拠: finance-api のレビュー指摘 (接続先未定のまま Derby 前提で書かれていた、2026-09-06) と T-010 の Derby 実測 (値を変えない UPDATE で affectedRows: 1、2026-09-07)。

## `db:select` の結果に `payload[0]` を無防備に取らない
0 件だと `Cannot coerce Null to String` で落ち、`ANY` を拾うハンドラがあると
アプリ内部の不整合が「基幹系に接続できません」として報告される。
select の直後に件数を確認してエラーを上げる。**DataWeave 側に `default` を足して隠さない。**
空の読み戻しは正常系ではない。
根拠: finance-api のレビュー指摘 (2026-09-06)。

## `db:select` の大量行を `foreach` で同じ DB に書くとデッドロックする組み合わせ
`non-repeatable-iterable` はイテレート中に接続を保持するので、`maxPoolSize` が小さいと `foreach` 内の `db:update` が接続を取れず止まる。
既定の `repeatable-file-store-iterable` は結果をバッファして接続を返すので起きない。`scatter-gather` の並列数以上の `maxPoolSize` を取る。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。


---

# DataWeave

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

## `dw validate` は `p()` を解決できない (フックの誤検知)
`Unable to resolve reference of: \`p\`` が出るが、`p()` は実行時にランタイムが解決する。
`.dwl` を検査するフックはこれを実エラーとして扱わないこと。
根拠: finance-api で `quick-check.sh` が編集をブロックした (2026-09-06)。

## DataWeave の予約語をキー名やセレクタに使わない
`type` `input` `default` `if` `as` `is` `do` `for` `var` `fun` `using` `yield` `and` `or` `not` `case` `else` `enum` `import` `ns` `null` `output` `private` `throw` `unless` `async` などをキー名やセレクタに使うと
`Invalid field name identifier. Reason: The name 'X' is a reserved word`。使うならクォート: `payload.'type'`、`{ 'input': ... }`。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。


---

# 配備 (CloudHub 2.0 / Runtime Fabric)

## CloudHub 2.0 は Exchange 経由でしか配備できない
jar を直接上げる口が無い。CH1 との一番大きな違い。mule-maven-plugin 経由でも
`404 Failed to retrieve artifact information from Exchange` で弾かれる。

そのため **`groupId` を組織 ID にする必要がある** (Exchange の資産の要件)。
`com.mycompany` のままでは公開できない。組織内の既存資産を見れば形が分かる。
`version` も上げ続ける必要がある。Exchange は同一版を上書きできない。
根拠: T1 organization への配備で実測 (2026-09-06)。

## CloudHub 2.0 の公開エンドポイントは `--publicEndpoints` では付かない
`anypoint-cli-v4 runtime-mgr application modify --publicEndpoints <host>` は
成功を返すが `access: internal` のまま変わらない。ホスト名だけでも
`https://` 込みの完全な URL でも同じ。

実体は `deploymentSettings.generateDefaultPublicUrl` で、CLI からは立てられない。
Application Manager の API を直接 PATCH する。

```
PATCH /amc/application-manager/api/v2/organizations/{org}/environments/{env}/deployments/{id}
{"target":{"targetId":"...","provider":"MC","replicas":1,
           "deploymentSettings":{"generateDefaultPublicUrl":true,"http":{"inbound":{"pathRewrite":"/"}}}}}
```
根拠: CH2 private space への配備で実測 (2026-09-06)。

## `runtime-mgr application modify` は properties を消す
`--property` / `--secureProperty` を付けずに `modify` を打つと、既に設定してある
アプリケーションプロパティが **空になる**。公開エンドポイントやレプリカ数だけを
変えたつもりが、DB の資格情報ごと飛ぶ。`modify` のたびに付け直す。

版を上げる `--assetVersion` は `Provided GAV is either incomplete or invalid` で
落ちる。`--groupId` を明示しても同じ。API の PATCH で
`application.ref.version` を書き換えるのが確実。
根拠: CH2 への再配備で 2 回とも実測 (2026-09-06)。

## RTF はコンソールログが既定で無効
`kubectl logs` でアプリのログを見るには `KubernetesTemplate` (名前は `mule-application` 固定、namespace `rtf`) で `ENABLE_CONSOLE_LOG: "true"` を立て、再配備する。
Anypoint Monitoring を使うと自動で無効化されることがある。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## RTF のアプリに Flex Gateway から届かせるには LoadBalancer サービスが要る
Flex Gateway が RTF 上の Mule アプリへルーティングする経路は、アプリを配備しただけでは通らない。
`type: LoadBalancer` の Service を立て (`selector` は RTF アプリのラベル、`port`/`targetPort` は
アプリの listener ポート)、`kubectl get svc` で EXTERNAL-IP を確認し、**API Manager の API インスタンスの
Implementation URI にその IP を書く** (`http://<EXTERNAL-IP>:8081/`)。
疎通しないときは配備ではなくここを疑う。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## Flex Gateway に curl が届かないときは IPv6 を疑う (`curl -4`)
環境によっては `localhost` が IPv6 (`::1`) に解決され、Flex Gateway への接続が失敗する。
**`curl -4` で IPv4 を明示する**と通る。ゲートウェイの設定によっては `Host` ヘッダーも要る
(`curl -4 -k -H "Host: mule-dev.com" https://localhost:1443/api/...`)。
smoke-check が落ちたとき、アプリやポリシーを疑う前にここを 1 回試す。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。


---

# API Manager とポリシー

## API Manager のポリシーは「適用」だけでは効かない
ポリシーを適用して 201 が返り、API Manager の一覧にも出るのに、**API は無防備なまま**という
状態になる。経路にゲートウェイがいないため。API インスタンスの `status` が
`unregistered` で `deployment` が `null` なら、そのポリシーは何も守っていない。

施行させる道は 2 つ。**どちらを選ぶかで必要な設定がまるごと変わる。**

| 型 | 何が要るか |
|---|---|
| **Basic endpoint** | Mule アプリ側に autodiscovery (`api-gateway:autodiscovery`) の設定が要る |
| **Proxy** | インスタンスの target URL を **アプリの内部エンドポイント** にし、**アプリの公開エンドポイントを消す**。外部からはプロキシに入る |

適用しただけの状態を放置しないこと。**「ポリシーが付いている」という表示と実際の保護が
食い違うのは、ポリシーが無いより危険。**
根拠: CloudHub 2.0 の Mule アプリに client-id-enforcement を掛ける過程で実測 (2026-09-06)。
適用は 201、認証なしのリクエストは 200 のまま通った。

## autodiscovery は EE の成果物が要る
`com.mulesoft.mule.modules:mule-api-gateway-module` は EE 側にあり、
Exchange の entitlement が無い環境では **Maven でも解決できない** (1.3.0 / 1.4.0 / 1.5.0 /
1.6.0 を試して全滅)。`ee:transform` と同じ壁。

EE が使えない環境では Basic endpoint 型は選べない。Proxy 型 (Omni Gateway) を使う。
根拠: 4 版を `mvn dependency:get` で試して全滅 (2026-09-06)。

## API インスタンスは「その組織で動いている形」に合わせる
`anypoint-cli-v4 api-mgr api manage --type raml --deploymentType cloudhub2` で作ると
`technology: mule3` のインスタンスができ、配備が通らない。

**手探りする前に、同じ組織で既に配備されている API インスタンスを読むこと。**
`GET /apimanager/api/v1/organizations/{org}/environments/{env}/apis/{id}` の
`technology` `endpoint.apiGatewayVersion` `deployment.type` `deployment.targetName` を
写せば、その環境で通る形が分かる。

実例では既存 3 本がすべて `flexGateway` / `HY` / `gatewayVersion 1.13.4` / target `ft1` で、
同じ形にしたら 201 で通った。CH2 プロキシ (`type: CH2`) は同じ組織で 500 のままだった。
根拠: 3 度作り直してようやく通った (2026-09-06)。

## flexGateway のインスタンス作成と配備の細かい制約
API を直接叩いて作る場合の必須の形。CLI では作れない組み合わせがある。

| 項目 | 値 | 間違えたときの症状 |
|---|---|---|
| `endpoint.muleVersion4OrAbove` | **`null`** | `Argument "muleVersion4OrAbove" is invalid for ... flexGateway` |
| `endpoint.validation` | **`NOT_APPLICABLE`** | `Validation status is invalid for the provided proxy/mule version` |
| `gatewayVersion` (配備) | ゲートウェイの版 (例 `1.13.4`)。**ランタイムの版ではない** | `Deployment blocked due to incompatible Proxy Version` |
| `endpoint.proxyUri` の港 | ゲートウェイが開けている港のみ (例では 8081 / 8082)。**パスで分ける** | `Proxy must be deployed in a port that is available` |
| 利用者アプリの作成 | `POST /exchange/api/v2/organizations/{org}/applications?apiInstanceId=<id>` | `A target apiInstanceId or groupInstanceId is required` |

根拠: 上記すべて実測 (2026-09-06)。

---
