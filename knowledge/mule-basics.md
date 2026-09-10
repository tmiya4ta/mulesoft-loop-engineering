# Mule アプリの基礎知識 (実行エージェントが最初に読む) — 索引

Mule を知らないまま試行錯誤すると、1 本の API に半日かかる。**「知っていれば試さなくて済むこと」**だけを
主題別に `knowledge/basics/<主題>.md` に置いてあります。1 項目 = 1 事実。

**これは索引です。書く前に、これから触る主題だけを開く。`knowledge/basics/` を丸ごと読まない。**
根拠と症状の原文が必要になったら `knowledge/gotchas.md` の索引から該当主題を開く。

出典の印: `[G]` gotchas (このループでの実測あり) / `[S]` mulesoft-app-development スキル (既知情報。実測ではない) /
`[K]` K ファイル / `[D]` 公式ドキュメント / `[reference]` 写経元。
写経元そのものは `${CLAUDE_PLUGIN_ROOT}/template/reference/` (通った実装から抜いた global.xml / impl / MUnit)。
プラグイン内のパスは `bash scripts/plugin-root.sh <相対パス>` で解決する。

対象の版: Mule 4.12.2 / Java 17 / MUnit 3.7.4 / APIkit 1.12.6 / mule-maven-plugin 4.10.1 / CE。
版が違えば `gotchas/build.md` の表を見る。

## これから触るものから主題を選ぶ

| # | 主題 | ファイル | 行 | 中身 |
|---|---|---|---|---|
| 1 | プロジェクトの骨格 | `basics/build.md` | 15 | ディレクトリ、pom、コネクタの GAV、RAML の置き場 |
| 2 | 設定とプロパティ | `basics/config.md` | 12 | `configuration-properties`、環境別 YAML、secure プロパティ、`p()` |
| 3 | フローの構造 | `basics/flow.md` | 12 | main flow と APIkit の振り分け、実処理 flow は HTTP を知らない、応答の組み立て |
| 4 | エラー処理 (ここで一番時間が溶ける) | `basics/error-handling.md` | 16 | `on-error-continue` / `propagate`、エラー型、共通ハンドラ、`<try>` |
| 5 | DataWeave | `basics/dataweave.md` | 11 | 外部 `.dwl`、`dw validate`、null の扱い、型強制 |
| 6 | DB コネクタ | `basics/db.md` | 14 | 操作の使い分け、SQL は子要素、戻り値の形、プール |
| 7 | MUnit | `basics/munit.md` | 16 | `mock-when` / `assert` / `verify-call`、samples を `readUrl`、カバレッジ |
| 8 | ビルドと配備 | `basics/deploy.md` | 12 | 検証の速い順、Exchange 経由の配備、版上げ、API Manager、`settings.xml` |
| 9 | 命名と分割 (このプラグインの規約) | `basics/naming.md` | 11 | ファイル分割、flow 名、dwl 名、層の責務 |
| 10 | Batch / MCP / A2A | `basics/kind.md` | 25 | `kind` が `api` 以外のとき。**実測 ([G]) はまだ無く、方向づけだけ** |

MUnit を書く・直すときは、この 7 節より `mule-munit` スキル (踏む順のチェックリスト) が先です。
