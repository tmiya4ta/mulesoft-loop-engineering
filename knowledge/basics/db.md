# DB コネクタ

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- SQL は **子要素** `<db:sql>...</db:sql>`。`sql="..."` の属性は XSD で落ちる。SQL 文字列は `config/sql.yaml` に 1 文 1 プロパティで置き、flow では `${sql.xxx}` で参照する。[G][reference]
- `db:update` は **UPDATE / MERGE / TRUNCATE 専用**。INSERT は `db:insert`、DELETE は `db:delete`。`db:update` に INSERT を書くと `DB:BAD_SQL_SYNTAX (Query type must be one of ...)`。MERGE (upsert) は `db:update` で書く。[K][S]
- 戻り値: `db:select` は **行の配列** (0 件は `null` ではなく `[]`)。`db:update` / `db:insert` は **`{affectedRows: N, generatedKeys: {...}}` のオブジェクト** (配列に包まれない)。`db:delete` は **素の整数**。[K]
- `affectedRows` の意味は **DB 製品で違う**。Derby は WHERE に一致した行数、MySQL の既定は値が変わった行数。存在判定に使うと PUT の冪等性が壊れるので、**存在は更新後の `db:select` の読み戻しで判定する**。[G][K]
- TIMESTAMP 列は Mule に入った時点で **DataWeave の String** (`2026-09-05T16:47:13.033`、TZ 無し)。`as String` は恒等変換。[K]
- `db:*` に `target="x"` を付けると `mock-when` の値が変数に入らず実 DB へ行く。`target` を外して `payload` を直接使う。[G]
- 列名・表名・スキーマ修飾は **推測しない**。`context/environment/` の定義から写す。MUnit は SQL を一度も実行しないので、間違えても全部緑のまま配備先で 500 になる。[G]
- JDBC ドライバは pom の **2 箇所**に要る。`<dependency>` (version あり) と、mule-maven-plugin の `<sharedLibraries><sharedLibrary>` (**version なし**)。ドライバは mule-plugin ではない素の jar なので、共有ライブラリに宣言しないとコネクタから見えない。**MUnit は db:* を mock するので片方だけでも緑のまま通り、配備して初めて落ちる。**書き方は `template/reference/pom-fragments.xml`。[G]
