# reference/ — 通った実装から抜いた写経元

**`kind: api` (RAML + APIkit) 専用。** `batch` / `mcp` / `a2a` にはまだこの形の雛形が無い (`knowledge/basics/kind.md` を参照)。

TDD で 1 本通った System API (finance-api、Mule 4.12.2 / APIkit 1.12.6 / DB 1.16.3 / MUnit 3.7.4) から、
**どの API でも同じ形になる部分**だけを抜いて名前を一般化したもの。実行エージェントは新しいファイルを
書く前にここを読み、同じ形で書く。ここに無い部品 (SAP、Salesforce、HTTP request) は
gotchas → スキル (platform-assistant) → マニュアルの順で調べる。

| ファイル | 何の写経元か |
|---|---|
| `global.xml` | 設定の読み込み、HTTP listener、APIkit config、DB config、**既定エラーハンドラ (problem+json)**、独自エラー型の登録スタブ |
| `api-main.xml` | 受け口 (listener + apikit:router) と、APIkit が振り分ける flow。実処理は `flow-ref` するだけ |
| `resource-impl.xml` | 実処理の flow。`<try>` + トランザクション + 読み戻しで存在判定 + ローカル error-handler |
| `resource-test.xml` | MUnit。samples を `readUrl` で読む、`doc:name` で mock を特定、エラー型を `then-return` で起こす、`verify-call` |
| `router-test.xml` | APIkit の振り分け flow を型付け attributes で直叩きする MUnit (3 つの形) |
| `error-types-test.xml` | 型登録スタブの MUnit。`expectedErrorType` で「型が登録されている」ことを検証する (`#[true]` を assert しない) |
| `dwl/problem.dwl` | RFC 7807 の本文。各 on-error は vars を立てるだけ |
| `dwl/problem-detail.dwl` | APIkit の `error.description` から項目名を取り出し文言表を引く |
| `config/sql.yaml` | SQL は 1 文 1 プロパティ。flow では `${sql.x}` |
| `config/messages.yaml` | 400 の項目別文言 |
| `pom-fragments.xml` | `api/` と `samples/` をクラスパスに乗せる `<resources>` / `<testResources>` |

例の名前は `customer-api` / リソース `profile` (PUT /customers/{customerId}/profile) / 接続先 `crm` / 表 `CUSTOMERS` / 独自エラー `APP:CUSTOMER_NOT_FOUND`。実際の名前に置き換えて使う。
`doc:name` は日本語の 1 句で、同じファイル内で一意にする (MUnit の mock がこれで操作を特定する)。

## patterns/ — よく使う部品の型 (**未実測**)

上の表のファイルと違い、`patterns/` は通ったビルドから抜いたものでは**ない**。出所はファイル冒頭に
ブロック単位で記してある (`[G][K]` = `knowledge/basics/` の実測事実、`[S]` = 利用者の
`mulesoft-app-development` スキル、`[D]` = 公開ドキュメント、`【未確認】` = **そのまま写さず、
書く前に `anypoint-cli-v4 dx mule describe-connector` か公式マニュアルで要素名を確かめる**)。

**全部読まない。使うコネクタのファイルだけ読む。**

| ファイル | 読むとき |
|---|---|
| `patterns/http-request.xml` | 外部の HTTP / REST を**呼ぶ**とき (Process / Experience 層、SaaS を包む System API)。request-config と認証、uri-params / query-params、responseTimeout、`http:response-validator`、`HTTP:*` のエラー型、`http:request` の MUnit mock |
| `patterns/db-operations.xml` | DB で `db:update` / `db:select` **以外**を使うとき。INSERT / DELETE / 一括投入 / ストアド、接続プールとベンダ別接続、大量 SELECT + foreach のデッドロック回避、各オペレーションの戻り値の形と MUnit mock |

`db:update` (UPDATE / MERGE) と `db:select` だけで足りるなら `patterns/` は要らない。`resource-impl.xml` に実測済みの形がある。
