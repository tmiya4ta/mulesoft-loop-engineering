# 命名と分割 (このプラグインの規約)

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- flow: `<動詞>-<対象>` (`change-address`)。APIkit の受け口は生成名のまま。sub-flow は使わず flow にする (`coverage-check.sh` が数える単位)。
- dwl: `<出力の型>.dwl` (`address-change-result.dwl`、`problem.dwl`)。
- 設定: `config/<用途>.yaml` (`sql.yaml`、`messages.yaml`、`<接続先>.yaml`)。
- テスト: `<resource>-test.xml`、テスト名は samples のケース名 (`address-ok`、`address-not-found`)。
- `doc:name` は **日本語の 1 句**で、`mock-when` の特定に使うので同じファイル内で一意にする。
