<!-- mule-loop -->
layer: __LAYER__
name: __NAME__

# このリポジトリの規則 (Claude Code 向け)

- 仕様は `api/*.raml` が唯一の正。実装より先に RAML を直す。
- 用語は `CONTEXT.md` の用語集に従う。無い語は勝手に作らず、そこに足す。
- フローは `src/main/mule/` に 1 リソース 1 ファイル。共通のエラーハンドラは `global.xml`。
- 変換は `src/main/resources/dwl/` に置き、必ず対の MUnit を `src/test/munit/` に書く。
- `samples/<resource>/<case>.in.json` と `.out.json` が受け入れ条件。**期待値は変えない。**
- 層の責務:
  - system: 外部システム 1 つを包む。ビジネスロジックを持たない。
  - process: system API だけを呼ぶ。DB / SAP / Salesforce コネクタを直接使わない。
  - experience: process か system を呼び、利用者向けに形を整える。永続化しない。
- 実装は TDD。先に MUnit を書いて失敗を確認し (Red)、通る最小の実装 (Green)、通ったまま整える (Refactor)。`mule-tdd` スキルの順に従う。
- 検証は速い順に `dw` → `mvn -q test -Dmunit.test=<対象ファイル>` → `mvn -q test`。
- フロー生成に公式スキル `build-mule-integration` や MCP `generate_mule_flow` を使ってよい。生成物は MUnit が通るまで仮説。
- ゴールは `tasks/T-*.md`。`done_when` の無いゴールは作らない。
- 人に判断を求めるのは `context/decisions.yaml` の空欄を最初に 1 回まとめて聞くときと、受け入れ条件の承認、PR マージ、本番、昇格 PR だけ。途中で迷ったら `decisions.yaml` の `defaults` で決めて `docs/spec/<name>.md` の「仮定」に残す。
- デプロイは `/mule-deploy` だけが行い、`context/deployment/authorizations.yaml` が `allowed` で人が明示的に指示したときに限る。本番は人が行う。
