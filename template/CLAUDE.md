<!-- mule-loop -->
kind: __KIND__
layer: __LAYER__
name: __NAME__

# このリポジトリの規則 (Claude Code 向け)

- 仕様は `api/*.raml` が唯一の正。実装より先に RAML を直す。
- 用語は `CONTEXT.md` の用語集に従う。無い語は勝手に作らず、そこに足す。
- フローは `src/main/mule/` に 1 リソース 1 ファイル。共通のエラーハンドラは `global.xml`。
- 変換は `src/main/resources/dwl/` に置き、必ず対の MUnit を `src/test/munit/` に書く。
- `samples/<resource>/<case>.in.json` と `.out.json` が受け入れ条件。**期待値は変えない。**
- 層の責務 (`kind: api` のときだけ。`batch` / `mcp` は層分けの対象外):
  - system: 外部システム 1 つを包む。ビジネスロジックを持たない。
  - process: system API だけを呼ぶ。DB / SAP / Salesforce コネクタを直接使わない。
  - experience: process か system を呼び、利用者向けに形を整える。永続化しない。
- `kind: batch` / `mcp` はまだこのプラグイン専用の `template/reference/` 雛形が無い (`knowledge/mule-basics.md` の
  「10. Batch / MCP / A2A」参照)。困ったら gotchas → スキル (platform-assistant 経由の mulesoft-app-development) →
  マニュアルの順で調べる。`kind: a2a` はこのリポジトリでは扱わない (`agent-network` 系スキルの担当)。
- 実装は TDD。先に MUnit を書いて失敗を確認し (Red)、通る最小の実装 (Green)、通ったまま整える (Refactor)。`mule-tdd` の順に従う。
- **スキルは名前ではなくパスで参照する。** 実行エージェントは Skill ツールを持たないので、`bash scripts/plugin-root.sh --skill <名前>` で SKILL.md の絶対パスに解決してから Read する。exit 1 なら入っていないので探し回らず、gotchas → `reference/mule-schema/INDEX.md` → マニュアルの順に戻る。
- 検証は速い順に `dw` → `mvn -q test -Dmunit.test=<対象ファイル>` → `mvn -q test`。
- フロー生成に MCP `generate_mule_flow` や公式スキル `build-mule-integration` (`--skill` で在否を確かめる。外部スキルなので無いことがある) を使ってよい。生成物は MUnit が通るまで仮説。
- ゴールは `tasks/T-*.md`。`done_when` の無いゴールは作らない。
- **台帳の外で作業しない。** 実装もデプロイもポリシーも `tasks/T-*.md` のゴール (stage: impl | deploy | policy) にしてから動く。done_when が無い作業は始めない。
- 実行エージェントは書く前にプラグインの `knowledge/mule-basics.md` と `template/reference/`、それに `reference/mule-schema/INDEX.md` (コネクタの要素名と操作名の地の情報) を読み、同じ形で書く。プラグイン内のパスは `bash scripts/plugin-root.sh <相対パス>` で解決する。困ったら gotchas → スキル (platform-assistant) → マニュアルの順で調べ、1 回でも詰まったことは `knowledge/K-<ゴール id>-<連番>.md` に残す。
- **進捗エージェントはマニュアルを読まない。** 読むのは台帳、context/、knowledge/ だけ。足りない事実は実行エージェントに調べさせ、`knowledge/K-NNN.md` に書かせてから使う。
- 止まるときは必ず「現在地 / 次にすること / そのあと」の 3 ブロックで締め、次にすることは 1 つ。
- 人に判断を求めるのは `context/decisions.yaml` の空欄を最初に 1 回まとめて聞くときと、受け入れ条件の承認、PR マージ、本番、昇格 PR だけ。途中で迷ったら `decisions.yaml` の `defaults` で決めて `docs/spec/<name>.md` の「仮定」に残す。
- デプロイは `/mule-deploy` だけが行い、`context/deployment/authorizations.yaml` の `deploy.sandbox` が `allowed` で、台帳に `stage: deploy` のゴールがあるときに限る。**会話での言い直しは求めない** (許可はファイルに書いてあり、二度確かめない)。可否は `deploy-guard.sh` が hook で判定するので、deny が返ったら理由をそのまま人に伝えて止まる。回避経路を探さない。本番は人が行う。
