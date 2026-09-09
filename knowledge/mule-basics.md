# Mule アプリの基礎知識 (実行エージェントが最初に読む)

Mule を知らないまま試行錯誤すると、1 本の API に半日かかる。ここは **「知っていれば試さなくて済むこと」** だけを
主題別にまとめた。1 項目 = 1 事実。出典は末尾の `[G]` (gotchas.md、実測あり) / `[S]` (mulesoft-app-development スキル) /
`[K]` (finance-api の K ファイル) / `[D]` (公式ドキュメント)。判断に迷ったら `knowledge/gotchas.md` の該当節で根拠を見る。
写経元は `${CLAUDE_PLUGIN_ROOT}/template/reference/` (通った実装から抜いた global.xml / impl / MUnit)。

対象の版: Mule 4.12.2 / Java 17 / MUnit 3.7.4 / APIkit 1.12.6 / mule-maven-plugin 4.10.1 / CE。版が違えば gotchas の表を見る。

---

## 1. プロジェクトの骨格

- 骨格は **CLI か MCP で作る**。手書き pom はライブラリ取得で必ず落ちる (`<extensions>true</extensions>`、`mule-application` パッケージング、Exchange と MuleSoft のリポジトリ定義、`mule-artifact.json` のどれかが欠ける)。`anypoint-cli-v4 dx mule project create <name> --group-id <組織 ID> --mule-version 4.12.2`。[G]
- 生成直後の pom に **MUnit は入っていない** (CLI も Studio も同じ)。`scripts/add-munit.sh` で足す。[G]
- CLI は mule-maven-plugin を **4.7.0 で固定する**が 4.12 系とは非互換 (`NoSuchMethodError: MuleRuntimeFeature.isEnabled`)。`scripts/fix-plugin-version.sh` で 4.10.1 に上げる。[G]
- **Mule 4.9.0 は使わない** (`mule-runtime-impl-no-services-bom` が公開されておらず、`ee:transform` を 1 つ書いた時点で MUnit が `Cannot create embedded container`)。4.10.1 以降、既定は 4.12.2。[G]
- Java は **17** (4.6 以降)。Java 25 は `java.lang.Compiler` が無く動かない。`javac` と `java` が別 JDK を指す環境があるので、スクリプトから呼ぶときは `readlink -f $(command -v java)` の隣の `javac` を使う。[S][K]
- `groupId` は **Anypoint の組織 ID (UUID)**。Exchange 経由の配備 (CH2 / RTF) はこれが要件。`com.example` のままでは配備できない。[G]
- 置き場所: フローは `src/main/mule/` (1 リソース 1 ファイル + `global.xml`)、変換は `src/main/resources/dwl/`、設定は `src/main/resources/config/*.yaml`、RAML は `api/` (pom の `<resources>` に `api/` を足さないとクラスパスに乗らず `Raml not found`)。[G]
- `mule-artifact.json` は `minMuleVersion` と `requiredProduct` を持つ。`ee:` 名前空間を 1 つ使うと `requiredProduct` が `MULE_EE` になり、MUnit が EE の器を作ろうとする (4.10.1 以降なら動く)。[G]
- `-DattachMuleSources` を付けてビルドすると jar に `META-INF/mule-src/` が入り、Studio で読める。Exchange に上げるなら付ける。[S]

## 2. 設定とプロパティ

- `<configuration-properties file="config/x.yaml"/>` は複数置ける。**YAML の値はすべて文字列**になる (数値が要る batch の `blockSize` などは YAML でクォートしない)。[S][K]
- `<global-property name="mule.env" value="local"/>` を **`configuration-properties` より前**に置いて既定値を作る。`${mule.env:local}` のような既定値付き参照は RTF で解決に失敗することがある。[S]
- ローカル実行 (`mvn test`) で `${x.y}` を上書きできるのは **システムプロパティ `-Dx.y=...` だけ**。OS の環境変数は `x.y` でも `X_Y` でも読まれない。CH2 / RTF では Runtime Manager の Properties が効く。[K]
- 秘密は `secure::` プロパティか配備時の secureProperty。pom / YAML / 会話に書かない。[S]
- `p('a.b.c')` で YAML のネストしたキーを動的に引ける。エラーハンドラの中で `readUrl` を使うと、その失敗が「エラーハンドラの中の 2 つ目のエラー」になって problem+json を名乗る壊れた応答を返すので、文言表は `configuration-properties` で起動時に読む。[G]
- Config 名は global と参照側で完全一致させる (`config-ref="process-api-config"`)。違うと起動時ではなく実行時に落ちる。[S]

## 3. フローの構造

- 受け口は `http:listener` (`path="/api/*"`) + `apikit:router` を持つ main flow 1 つ。APIkit が RAML のメソッドとパスから `put:\customers\(customerId)\address:application\json:<config>` という名前の flow に振り分ける。この flow は `attributes.uriParams` を `vars` に立てて **実処理の flow に `flow-ref` するだけ**にする。[reference]
- 実処理の flow (`change-address` など) は HTTP を知らない。入力は `vars` と `payload`、出力は `payload` と `vars.httpStatus`。これで MUnit から `flow-ref` 直叩きできる。[reference]
- `http:listener` の応答は `<http:response statusCode="#[vars.httpStatus default 200]">` と `<http:error-response statusCode="#[vars.httpStatus default 500]">` で `vars` から取る。`apikit:config` の `httpStatusVarName="httpStatus"` / `outboundHeadersMapName="outboundHeaders"` と揃える。[reference]
- `attributes.requestPath` は listener のベースパス込み (`/api/customers/...`)。RAML のリソースパスと比べるときは `/api` を剥がす。[G]
- インライン DataWeave はフローに書かない。`<ee:transform>` から `resource="dwl/x.dwl"` で参照する。`dw validate -f x.dwl` で秒単位に検査できる (`p()` と `payload`/`vars` の未解決は誤検知)。[G]
- `db:select` で大量行を `foreach` して同じ DB に書くとき、`non-repeatable-iterable` + 小さい `maxPoolSize` はデッドロックする。既定 (`repeatable-file-store-iterable`) のままにし、`scatter-gather` の並列数以上の `maxPoolSize` を取る。[S]

## 4. エラー処理 (ここで一番時間が溶ける)

- **エラー型は `NAMESPACE:IDENTIFIER`**。コネクタのもの (`DB:CONNECTIVITY`、`HTTP:NOT_FOUND`、`APIKIT:BAD_REQUEST`)、コアのもの (`MULE:EXPRESSION`、`ANY`)、アプリ独自のもの (`APP:CUSTOMER_NOT_FOUND`)。独自型は **`raise-error` が最低 1 箇所無いとビルドが通らない** (`Could not find error 'APP:X'`)。TDD でハンドラを先に書くときは到達しない分岐に 1 つ置く。[G]
- **コネクタの型は `raise-error` できない**。テストで `DB:CONNECTIVITY` を起こしたいなら `mock-when` の `then-return` に `<munit-tools:error typeId="DB:CONNECTIVITY"/>` を置く。[G]
- ハンドラは 2 種類。`on-error-continue` はエラーを **処理して正常応答扱い**にする (flow は成功として終わる)。`on-error-propagate` は **処理してから再送出**する (外側へ伝わる)。[D]
- `<configuration defaultErrorHandler-ref="global-error-handler"/>` は **全 flow と、error-handler を持たない全 `<try>` の既定**になる。`<try>` にも適用されるので、既定の `on-error-continue` が処理すると **`<try>` の直後から実行が続く**。成功時にしか意味の無い処理 (読み戻し後の変換など) を `<try>` の後ろに置くと、エラー処理の後でそれが走り 404 が 502 に化ける。**成功時だけの処理は同じ `<try>` の中 (`choice` の `otherwise`) に閉じ込める。**[G][K]
- 共有の `global-error-handler` に `on-error-propagate` を足すと、`<try>` を持たない flow では応答を返す前にエラーが外へ抜けて壊れる。巻き戻しが要る flow の `<try>` の中に **ローカルの `<error-handler>`** を置き、そこで `on-error-propagate` する。`<error-handler>` は `<try>` の **最後の子要素**。[G]
- `ANY` は **接続エラーと別の枝**にする。`type="DB:*, ANY"` と書くと DataWeave の失敗やアプリの欠陥まで「基幹系に接続できません (502)」になる。`ANY` は最後の枝で 500 と `internal-error`。[G]
- `on-error-continue` の中で `vars.httpStatus` と `vars.outboundHeaders` を立て、`payload` を problem+json (RFC 7807) に変換すると、listener がそのまま返す。本文の組み立ては 1 つの `problem.dwl` に寄せ、各枝は `vars.problemType / problemTitle / problemDetail` を立てるだけにする。[reference]
- APIkit の検証エラー (`APIKIT:BAD_REQUEST`) の `error.description` は `/<項目名> string [値] does not match pattern ...` で始まり、複数なら改行連結。項目名を取り出して文言表を引ける。`NOT_ACCEPTABLE` / `UNSUPPORTED_MEDIA_TYPE` はこの形にならないので既定文を用意する。[G]
- `mock-when` は操作に付けた `error-mapping` ごと無効化する。エラー型の写し替えは操作の外 (`<try>` + `on-error-propagate`) で行う。[G]
- トランザクションは `<try transactionalAction="ALWAYS_BEGIN">`。commit / rollback は **MUnit では観測できない** (mock は接続を取らない)。テストで言えるのは「巻き戻しの経路を通った」までなので、`vars.rollbackTriggered` のような印を立てて検証する。[G]

## 5. DataWeave

- ヘッダは `%dw 2.0` + `output application/json`。`---` の後が本体。
- **予約語をキー名やセレクタに使わない** (`type`、`input`、`default`、`if`、`as`、`is`、`do`、`for`、`var`、`fun`、`using`、`yield` など)。使うならクォート: `payload.'type'`、`{ 'input': ... }`。違反時は `Invalid field name identifier ... reserved word`。[S]
- `default` は null 安全のためだが、**assert の式や存在判定に付けると検証を無効化する**。`payload[0]` を無防備に取ると 0 件で `Cannot coerce Null to String`。**空を `default` で隠さず、`isEmpty(payload)` で判定して `raise-error` する。**[G]
- `http:request` の応答は MIME が JSON なら既に解釈済みで、`payload as String` は `Cannot coerce Object to String`。文字列で扱うなら `outputMimeType="application/java"` を付ける。[G]
- 大きな入力は `outputMimeType="application/json; streaming=true"` と `output ... deferred=true`。ストリーミング中は同じ値を 2 回参照できない (`x ++ x`、`payload[-1]` は不可)。[S]

## 6. DB コネクタ

- SQL は **子要素** `<db:sql>...</db:sql>`。`sql="..."` の属性は XSD で落ちる。SQL 文字列は `config/sql.yaml` に 1 文 1 プロパティで置き、flow では `${sql.xxx}` で参照する。[G][reference]
- `db:update` は **UPDATE / MERGE / TRUNCATE 専用**。INSERT は `db:insert`、DELETE は `db:delete`。`db:update` に INSERT を書くと `DB:BAD_SQL_SYNTAX (Query type must be one of ...)`。MERGE (upsert) は `db:update` で書く。[K][S]
- 戻り値: `db:select` は **行の配列** (0 件は `null` ではなく `[]`)。`db:update` / `db:insert` は **`{affectedRows: N, generatedKeys: {...}}` のオブジェクト** (配列に包まれない)。`db:delete` は **素の整数**。[K]
- `affectedRows` の意味は **DB 製品で違う**。Derby は WHERE に一致した行数、MySQL の既定は値が変わった行数。存在判定に使うと PUT の冪等性が壊れるので、**存在は更新後の `db:select` の読み戻しで判定する**。[G][K]
- TIMESTAMP 列は Mule に入った時点で **DataWeave の String** (`2026-09-05T16:47:13.033`、TZ 無し)。`as String` は恒等変換。[K]
- `db:*` に `target="x"` を付けると `mock-when` の値が変数に入らず実 DB へ行く。`target` を外して `payload` を直接使う。[G]
- 列名・表名・スキーマ修飾は **推測しない**。`context/environment/` の定義から写す。MUnit は SQL を一度も実行しないので、間違えても全部緑のまま配備先で 500 になる。[G]

## 7. MUnit

- 1 テストファイル = 1 リソース (`src/test/munit/<resource>-test.xml`)。samples の 1 ケース = 1 `munit:test`。構造は `behavior` (mock) → `execution` (`flow-ref`) → `validation` (`assert-that`)。[reference]
- 入力と期待値は `readUrl("classpath://samples/<r>/<case>.in.json", "application/json")` で **samples から直接読む**。書き写すと二重管理になってずれる。pom の `<testResources>` に `samples/` を足す。[reference]
- `mock-when` は `processor="db:update"` + `with-attribute attributeName="doc:name" whereValue="..."` で **doc:name で操作を特定**する。同じ processor が複数あるとき、doc:name 無しだと全部同じ値になる。[reference]
- MUnit は **既定でメッセージソースを起動しない**。実 HTTP を叩くテストは `<munit:enable-flow-sources>` で対象 flow を有効化しないと `Connection refused`。通常は `flow-ref` 直叩きで足りる。[G]
- APIkit の main flow を `flow-ref` で直叩きするには attributes を `HttpRequestAttributes` に型付けする (`... as Object {class: "org.mule.extension.http.api.HttpRequestAttributes"}`、`headers` と `queryParams` は `MultiMap`)。[G]
- **`default` 付きの assert は何も検証しない** (`#[vars.x default 1]` は未設定でも通る)。検出法: 参照する変数名を存在しないものに変えて通るなら牙が無い。呼び出しの事実は `verify-call` (`times="1"` + `attributeName="sql"`) で見る。[G]
- 分岐を変えたら **既存テストの `behavior` にモックを足す** (早期終了していた分岐が後続に到達して実 DB へ行く)。`assert` は変えない。[G]
- 絞り込みは `-Dmunit.test=<file>.xml` (`-Dtest=` は効かない)。`clean` を付けないと「already been run」で実行されず BUILD SUCCESS が返る。[G]
- CE で失われるのは **カバレッジ計測だけ** (`ee:transform` も `batch` も動く)。`requiredApplicationCoverage` は CE では警告だけ。保証は `scripts/coverage-check.sh` (全 flow が `flow-ref` される) と、samples のケース数。[G]
- MUnit が検証しないもの: **SQL 文の正しさ、listener の直列化、実接続、トランザクション**。ここは配備後の `smoke-check.sh` (段 4) が見る。[G]

## 8. ビルドと配備

- ローカル検証は速い順: `dw validate` → `mvn -q clean test -Dmunit.test=<file>` → `mvn -q clean test` → `mvn -q clean package -DskipTests` (XSD 検証はここで初めて走る)。[reference]
- CH2 / RTF は **Exchange 経由のみ**。`mvn clean deploy -DmuleDeploy` (`scripts/deploy-config.sh` が pom に設定を入れる)。Exchange は同一版を上書きできないので **配備ごとに `scripts/bump-version.sh`**。[G]
- CH2 の公開 URL は `--publicEndpoints` では付かない。`scripts/ch2-public-url.sh` (Application Manager API の `generateDefaultPublicUrl`)。`runtime-mgr application modify` は **properties を消す**。[G]
- RTF はコンソールログが既定で無効。`KubernetesTemplate` (`ENABLE_CONSOLE_LOG: "true"`、名前は `mule-application`、namespace `rtf`) を作って再配備。[S]
- API Manager のポリシーは **適用しただけでは効かない** (201 が返っても経路にゲートウェイがいない)。Basic endpoint (autodiscovery、EE 必須) か Proxy (Flex) を選び、`scripts/policy-check.sh` (認証なし 401、あり 2xx) で判定する。[G]
- `~/.m2/settings.xml` には Maven Central と `anypoint-exchange-v3` (Connected App: `~~~Client~~~` / `<id>~?~<secret>`) が要る。EE の Nexus は資格情報が無ければコメントアウト。401 は `.classpath` の EE コネクタ参照か EE リポジトリの認証欠け。[S]

## 9. 命名と分割 (このプラグインの規約)

- flow: `<動詞>-<対象>` (`change-address`)。APIkit の受け口は生成名のまま。sub-flow は使わず flow にする (`coverage-check.sh` が数える単位)。
- dwl: `<出力の型>.dwl` (`address-change-result.dwl`、`problem.dwl`)。
- 設定: `config/<用途>.yaml` (`sql.yaml`、`messages.yaml`、`<接続先>.yaml`)。
- テスト: `<resource>-test.xml`、テスト名は samples のケース名 (`address-ok`、`address-not-found`)。
- `doc:name` は **日本語の 1 句**で、`mock-when` の特定に使うので同じファイル内で一意にする。
