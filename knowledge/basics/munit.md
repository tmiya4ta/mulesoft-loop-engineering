# MUnit

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

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
