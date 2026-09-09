# reference/ — 通った実装から抜いた写経元

TDD で 1 本通った System API (finance-api、Mule 4.12.2 / APIkit 1.12.6 / DB 1.16.3 / MUnit 3.7.4) から、
**どの API でも同じ形になる部分**だけを抜いて名前を一般化したもの。実行エージェントは新しいファイルを
書く前にここを読み、同じ形で書く。ここに無い部品 (SAP、Salesforce、HTTP request) は `mule-basics.md` の
「困ったら」の順で調べる。

| ファイル | 何の写経元か |
|---|---|
| `global.xml` | 設定の読み込み、HTTP listener、APIkit config、DB config、**既定エラーハンドラ (problem+json)** |
| `api-main.xml` | 受け口 (listener + apikit:router) と、APIkit が振り分ける flow。実処理は `flow-ref` するだけ |
| `resource-impl.xml` | 実処理の flow。`<try>` + トランザクション + 読み戻しで存在判定 + ローカル error-handler |
| `resource-test.xml` | MUnit。samples を `readUrl` で読む、`doc:name` で mock を特定、エラー型を `then-return` で起こす、`verify-call` |
| `dwl/problem.dwl` | RFC 7807 の本文。各 on-error は vars を立てるだけ |
| `dwl/problem-detail.dwl` | APIkit の `error.description` から項目名を取り出し文言表を引く |
| `config/sql.yaml` | SQL は 1 文 1 プロパティ。flow では `${sql.x}` |
| `config/messages.yaml` | 400 の項目別文言 |
| `pom-fragments.xml` | `api/` と `samples/` をクラスパスに乗せる `<resources>` / `<testResources>` |

例の名前は `customer-api` / リソース `profile` (PUT /customers/{customerId}/profile) / 接続先 `crm` / 表 `CUSTOMERS` / 独自エラー `APP:CUSTOMER_NOT_FOUND`。実際の名前に置き換えて使う。
`doc:name` は日本語の 1 句で、同じファイル内で一意にする (MUnit の mock がこれで操作を特定する)。
