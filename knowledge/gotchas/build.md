# プロジェクトとビルド (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

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

## ベンダの JDBC jar は fat jar とは限らない (依存を宣言しているだけ)

**症状**: `clouderby-jdbc-1.5.0.jar` を `java -cp` に 1 つだけ渡して繋ぐと
`NoClassDefFoundError: com/fasterxml/jackson/databind/ObjectMapper`。

**原因**: この jar は依存を同梱した fat jar ではなく、`jackson-databind` を compile 依存として
**宣言しているだけ**。ファイル名も大きさも fat jar と区別が付かないので、1 個で足りると思い込む。

**直し方**: クラスパスを推測せず Maven に出させる。
`mvn -o dependency:build-classpath -Dmdep.outputFile=cp.txt` の結果を `java -cp "$(cat cp.txt):..."` に渡す。
接続確認のような Mule の外の小さな検証でも同じ。

**根拠**: finance-api T-009 (2026-09-07) で 1 回。DB への疎通を Mule の外で確かめようとして踏んだ。
