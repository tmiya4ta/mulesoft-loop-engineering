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

## `mock-when` は操作に付けた `error-mapping` ごと無効化する
`<munit-tools:mock-when>` は操作そのものを差し替えるので、その操作に付けた
`<error-mapping sourceType="..." targetType="..."/>` は効かない。
mock 経由ではエラー型が写し替わらず、テストだけが赤くなる。
エラー型の写し替えは操作の外 (`<try>` + `on-error-propagate`) に出す。
なお `error-mapping` は XSD 上 `db:sql` より前に置く必要があり、順を間違えると
配備前に `cvc-complex-type.2.4.a` で落ちる。
根拠: 一意制約違反を 409 に写す実装中に 2 段で露見 (2026-09-06)。

## `dx mule project create` は mule-maven-plugin 4.7.0 を固定する (4.12 系と非互換)
`--mule-version 4.12.2` を指定しても pom の `mule.maven.plugin.version` は 4.7.0 のままで、
`java.lang.NoSuchMethodError: 'boolean org.mule.runtime.features.api.MuleRuntimeFeature.isEnabled(java.util.Optional)'`
が出て `process-classes` で落ちる。Studio が生成する pom は 4.10.1 なのでこの問題は起きない。
`scripts/fix-plugin-version.sh` が app.runtime を見て 4.10 系に上げる。
根拠: CLI 生成 4.12.2 で 4.7.0 は exit 1、4.10.1 に上げると `ee:transform` 込みで
Tests run: 1 - Failed: 0 (2026-09-06)。

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
