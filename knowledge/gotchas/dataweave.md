# DataWeave (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す。他の主題と確認した版もそこに。

## DataWeave の検査は `dw validate -f`。`dw -f` は存在しない
dw CLI (Command Line V1.0.34) に単体の `-f` は無く、**正しい .dwl でも exit 2** を返す。
段 1 が全ての .dwl 編集を無条件に弾き、実行ループが進まなくなる。
さらに `dw validate` は Mule の dwl に 2 つの誤判定を出す。

| 誤判定 | なぜ Mule では正常か |
|---|---|
| `Missing Mapping Expression` | 変換を module (`---` を持たないファイル) に切り出すのは規則 5 が求める形 |
| `Unable to resolve reference of: payload` | `payload` `vars` `attributes` は実行時にしかない束縛 |

**module の本物の構文エラーは正しく捕まる** (`fun f(x) = x +` → `Missing addition expression`) ので、
この 2 つを除いた残りの `[ERROR]` だけを見れば検証器として使える。ANSI の色コードが混じるので
grep の前に落とす。`scripts/quick-check.sh` は修正済み。
根拠: System API 1 本の実装中に 2 段階で露見 (2026-09-06)。1 つ目は最初の .dwl 編集で即座に、
2 つ目は変換を module に切り出した直後に。module 正常 / module 壊れ / payload 参照 /
script 壊れ / 素の正常 / 素の壊れ / 実物 2 本の 8 通りで期待どおりを確認。

## `dw validate` は `p()` を解決できない (フックの誤検知)
`Unable to resolve reference of: \`p\`` が出るが、`p()` は実行時にランタイムが解決する。
`.dwl` を検査するフックはこれを実エラーとして扱わないこと。
根拠: finance-api で `quick-check.sh` が編集をブロックした (2026-09-06)。

## DataWeave の予約語をキー名やセレクタに使わない
`type` `input` `default` `if` `as` `is` `do` `for` `var` `fun` `using` `yield` `and` `or` `not` `case` `else` `enum` `import` `ns` `null` `output` `private` `throw` `unless` `async` などをキー名やセレクタに使うと
`Invalid field name identifier. Reason: The name 'X' is a reserved word`。使うならクォート: `payload.'type'`、`{ 'input': ... }`。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。
