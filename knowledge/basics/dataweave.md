# DataWeave

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- ヘッダは `%dw 2.0` + `output application/json`。`---` の後が本体。
- **予約語をキー名やセレクタに使わない** (`type`、`input`、`default`、`if`、`as`、`is`、`do`、`for`、`var`、`fun`、`using`、`yield` など)。使うならクォート: `payload.'type'`、`{ 'input': ... }`。違反時は `Invalid field name identifier ... reserved word`。[S]
- `default` は null 安全のためだが、**assert の式や存在判定に付けると検証を無効化する**。`payload[0]` を無防備に取ると 0 件で `Cannot coerce Null to String`。**空を `default` で隠さず、`isEmpty(payload)` で判定して `raise-error` する。**[G]
- `http:request` の応答は MIME が JSON なら既に解釈済みで、`payload as String` は `Cannot coerce Object to String`。文字列で扱うなら `outputMimeType="application/java"` を付ける。[G]
- 大きな入力は `outputMimeType="application/json; streaming=true"` と `output ... deferred=true`。ストリーミング中は同じ値を 2 回参照できない (`x ++ x`、`payload[-1]` は不可)。[S]
