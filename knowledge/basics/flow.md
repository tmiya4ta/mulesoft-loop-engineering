# フローの構造

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- 受け口は `http:listener` (`path="/api/*"`) + `apikit:router` を持つ main flow 1 つ。APIkit が RAML のメソッドとパスから `put:\customers\(customerId)\address:application\json:<config>` という名前の flow に振り分ける。この flow は `attributes.uriParams` を `vars` に立てて **実処理の flow に `flow-ref` するだけ**にする。[reference]
- 実処理の flow (`change-address` など) は HTTP を知らない。入力は `vars` と `payload`、出力は `payload` と `vars.httpStatus`。これで MUnit から `flow-ref` 直叩きできる。[reference]
- `http:listener` の応答は `<http:response statusCode="#[vars.httpStatus default 200]">` と `<http:error-response statusCode="#[vars.httpStatus default 500]">` で `vars` から取る。`apikit:config` の `httpStatusVarName="httpStatus"` / `outboundHeadersMapName="outboundHeaders"` と揃える。[reference]
- `attributes.requestPath` は listener のベースパス込み (`/api/customers/...`)。RAML のリソースパスと比べるときは `/api` を剥がす。[G]
- インライン DataWeave はフローに書かない。`<ee:transform>` から `resource="dwl/x.dwl"` で参照する。`dw validate -f x.dwl` で秒単位に検査できる (`p()` と `payload`/`vars` の未解決は誤検知)。[G]
- `db:select` で大量行を `foreach` して同じ DB に書くとき、`non-repeatable-iterable` + 小さい `maxPoolSize` はデッドロックする。既定 (`repeatable-file-store-iterable`) のままにし、`scatter-gather` の並列数以上の `maxPoolSize` を取る。[S]
