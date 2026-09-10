# APIkit と HTTP (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

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
