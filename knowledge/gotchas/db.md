# DB コネクタ (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

## `db:update` / `db:select` の SQL は属性ではなく子要素
`sql="..."` の属性で書くと XSD 検証で落ちる。`<db:sql>...</db:sql>` の子要素にする。
根拠: mule-db-connector 1.16.3、finance-api の T-003 で実測 (2026-09-06)。

## `db:update` は UPDATE / MERGE / TRUNCATE 専用。INSERT と DELETE は別オペレーション
`<db:update>` に INSERT 文を書くと DB に届く前に Mule 側で弾かれる:
`DB:BAD_SQL_SYNTAX: Query type must be one of [UPDATE, TRUNCATE, MERGE, STORE_PROCEDURE_CALL] but query '...' is of type 'INSERT'`。
INSERT は `<db:insert>`、DELETE は `<db:delete>`。MERGE (upsert) は `db:update` で書く (`db:insert` / `db:execute-script` は `input-parameters` が使えない)。
根拠: finance-api T-010 で実測 (mule-db-connector 1.16.3、2026-09-07)。MERGE は mulesoft-app-development スキル。

## DB コネクタの戻り値の形は操作ごとに違う
| 操作 | payload | 0 件のとき |
|---|---|---|
| `db:select` | 行の配列 (`[{COL: v, ...}]`) | `[]` (`null` ではない) |
| `db:update` / `db:insert` | `{affectedRows: N, generatedKeys: {...}}` のオブジェクト (配列に包まれない) | `affectedRows: 0` |
| `db:delete` | 素の整数 (`1`) | `0` |

`isEmpty(payload)` は `null` でも `[]` でも真なので、0 件判定にはこれを使う。
根拠: finance-api T-010 で実 Derby に対して 5 操作を実測 (2026-09-07)。

## TIMESTAMP 列が DataWeave に何型で来るかは **DB とドライバで違う**。`as String` を書かない

**症状 (Oracle)**: `row.LAST_UPDATED as String` が `MULE:EXPRESSION` /
`Cannot coerce Object to String` で落ち、curl が 500。**MUnit は 15 スイート全部緑のまま。**

**実測が真逆に出た 2 件**:

| 接続先 | `db:select` が DataWeave に渡す型 | `as String` |
|---|---|---|
| Derby (clouderby-jdbc) | 既に `String` (`2026-09-05T16:47:13.033`、TZ 無し) | 恒等変換で無害 |
| Oracle (`db:generic-connection`) | 素の `Object` | **落ちる** |

**この項目は以前「TIMESTAMP 列は String」と一般的な事実として書かれていました。** 出典は Derby 1 件の
実測で、Oracle では逆でした。**1 つの接続先での実測を、全接続先の事実として書いてはいけません。**

**直し方**: DataWeave 側で型を当てにしない。**SQL で文字列にしてから渡す。**
`TO_CHAR(i.last_updated, 'YYYY-MM-DD"T"HH24:MI:SS.FF3') AS last_updated` (Oracle)。
同じ列を読む SELECT が複数あれば**全部**直す (楽観ロックの比較経路も同じ列を読んでいた)。
dwl 側の `as String` は文字列に対する no-op として残してよい。

**MUnit では検出できません。** `mock-when` が返すのはプレーンな文字列なので、型の不一致は
モックで消えます (`gotchas/munit.md` の「mock-when は値の型を実物に合わせない」)。
気付けるのは配備先に実 DB で当てたときだけです。

根拠: finance-api T-010 (Derby、2026-09-07) と inventory2-api (Oracle XEPDB1、2026-09-09) で
**同じ列の型が逆に出た**。後者は 15 スイート緑・curl で 500 という形で出た。

---

## Oracle の接続文字列: SID と Service Name を取り違えやすく、PDB が違うと「接続できるのに表が無い」

**Oracle 固有の事実です** (JDBC の URL の形と、PDB という Oracle の仕組みの話)。

**形が 2 つある**:

| 形 | URL | 取り違えると |
|---|---|---|
| SID | `jdbc:oracle:thin:@host:port:SID` (**コロン**) | `ORA-12505: SID '<x>' is not registered with the listener` |
| Service Name | `jdbc:oracle:thin:@host:port/ServiceName` (**スラッシュ**) | — |

XE / PDB 構成では通常 **Service Name (スラッシュ)** を使います。`ORA-12505` は listener 自体は
応答していて、**パスワード検証にすら到達していない**サインです (資格情報を疑う前に URL の形を見る)。

**PDB が違うと、接続は成功するのに `ORA-00942: table or view does not exist`**。
1 つのインスタンスに複数の PDB (Pluggable Database) を持てるので、**同じホスト・ポート・ユーザー名でも
Service Name (= PDB) が違えば別のスキーマ空間**です。`ORA-00942` は「表が本当に無い」と
「**違う PDB に繋いでいる**」の両方で起き、後者は接続エラーにならないので気付きにくい。
DDL の適用を疑う前に、JDBC 直結で `SELECT table_name FROM user_tables` を流して**実際に見えるもの**を
確かめます。

**接続先ごとの値 (どの Service Name にどの表があるか) は `context/environment/` に書きます。**
ここに書くのは「Oracle ではこう取り違える」という形だけです (v0.6.23 の規則)。

根拠: inventory2-api T-010 / T-011 で 2 回実測 (2026-09-09〜10)。1 回目は URL の形 (コロン → スラッシュ)
で `ORA-12505` を解消、2 回目は Service Name の値の違いで `ORA-00942` を解消 (DDL は別の PDB に
適用されていた)。PR #7 の後半を、分割後のこのファイルに移植した。

---

## `affectedRows` の意味は DB 製品で違う (Derby は一致行数、MySQL は変更行数)
Derby は WHERE に一致した行数を返す (値を変えない UPDATE でも 1)。MySQL の既定は値が変わった行数を返す (同じ値の UPDATE は 0)。
`affectedRows == 0` を「対象が存在しない」と読むと、MySQL では同じ値の PUT が 404 になり冪等性が壊れる。
**存在判定は更新後の `db:select` の読み戻しで行う。** 接続先が未確定のまま書くときはとくに。
根拠: finance-api のレビュー指摘 (接続先未定のまま Derby 前提で書かれていた、2026-09-06) と T-010 の Derby 実測 (値を変えない UPDATE で affectedRows: 1、2026-09-07)。

## `db:select` の結果に `payload[0]` を無防備に取らない
0 件だと `Cannot coerce Null to String` で落ち、`ANY` を拾うハンドラがあると
アプリ内部の不整合が「基幹系に接続できません」として報告される。
select の直後に件数を確認してエラーを上げる。**DataWeave 側に `default` を足して隠さない。**
空の読み戻しは正常系ではない。
根拠: finance-api のレビュー指摘 (2026-09-06)。

## `db:select` の大量行を `foreach` で同じ DB に書くとデッドロックする組み合わせ
`non-repeatable-iterable` はイテレート中に接続を保持するので、`maxPoolSize` が小さいと `foreach` 内の `db:update` が接続を取れず止まる。
既定の `repeatable-file-store-iterable` は結果をバッファして接続を返すので起きない。`scatter-gather` の並列数以上の `maxPoolSize` を取る。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## Oracle へ sqlplus で UTF-8 の文字列を INSERT/UPDATE するとき、NLS_LANG を先に設定しないと不可逆に壊れる
**症状**: シード投入 (`sqlplus` で直接 INSERT/UPDATE) した日本語の値が、アプリ経由 (JDBC/Mule) で
読み出すと文字化けする。DataWeave の数値フォーマットの疑いで調べても再現しない
(`45.0` と `45` は jq でも同値なので、数値は原因ではない)。

**原因**: `sqlplus` はクライアント側の `NLS_LANG` 環境変数が無い/DB の文字集合と食い違う状態で
非 ASCII 文字を送ると、送信時点でバイト列を壊す。`DUMP(col,1016)` で見ると全バイトが
`ef,bf,bd` (= U+FFFD、置換文字) になっている — つまり **DB にもアプリにも非は無く、
投入コマンドの側で既に壊れた値が格納されている**。

**直し方**: `sqlplus` で UTF-8 のテキストを送る前に、DB の `NLS_CHARACTERSET` に合わせて
`export NLS_LANG=AMERICAN_AMERICA.AL32UTF8` してから実行する (`AL32UTF8` が Oracle の
UTF-8 文字集合名)。既に壊れた行は再 UPDATE で直す (再投入すれば直る。DDL からの作り直しは不要)。

根拠: inventory3-api T-006 で実測 (Oracle、2026-09-11)。`DUMP()` で全バイト `ef,bf,bd` を確認、
`NLS_LANG` 設定後の再 UPDATE で正しい日本語が格納されることを確認した。
