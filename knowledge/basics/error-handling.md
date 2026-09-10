# エラー処理 (ここで一番時間が溶ける)

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

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
