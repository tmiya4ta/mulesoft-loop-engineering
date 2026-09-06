---
name: mule-run
description: 台帳 tasks/ の未完了ゴールを予算内で実行エージェントに配り、done_when を自分で再実行して確かめ、証拠と試行ログを台帳に書き戻す計画・実行ループ。中断からの再開にも使う。
argument-hint: "[T-NNN だけ実行] [--parallel N]"
---

あなたは進捗エージェントです。実装は自分でせず、`mule-executor` に配ります。

## 配る前に必ず 3 つ確認する
1. `bash scripts/budget-check.sh` を実行する。**exit 1 なら 1 件も配らずに止まり**、人に残予算と状況を報告する。出力の `max_parallel` が `--parallel` の上限で、引数がそれを超えていたら切り下げる。
2. `context/sources.yaml` が埋まっているか。`requirements` が空で `note` も空なら、`/mule-start` に戻るよう案内して止まる。
3. ゴールに `done_when` があるか。無ければ止めて報告する。

## ループ
1. `tasks/T-*.md` を読み、`status` が `todo` または `failed` (attempts < 3) で、`blocked_by` が全て `passed` のものを取り出す。
2. 各ゴールについて:
   - `status: running` に更新する。
   - **モデルを選ぶ。** attempts 0〜1 は `sonnet`、attempts 2 (= 3 回目の挑戦) は `opus` に上げる。Agent 呼び出し時の `model` で指定する (frontmatter より呼び出し側が優先)。
   - `bash scripts/run-log.sh dispatch <id> <model>` を実行する。
   - Agent ツールで `mule-executor` を **`isolation: "worktree"`** で起動する。プロンプトはゴールファイルのパスと「CLAUDE.md と context/ を読んで規則に従うこと」だけ。
   - 配るたびに budget-check を再実行する (並列時も 1 件ごとに数える)。
3. 戻ってきたら diff を取り込み、**`done_when` を自分で実行する**。実行エージェントの自己申告は信じない。
   - `samples/` か `src/test/munit/` の期待値が変更されていたら、**diff を捨てて failed にする**。理由を試行ログに書く。
   - `red` の証拠が無い、または `red` と `green` が別コマンドなら failed にする。
   - exit 0 → `bash scripts/coverage-check.sh` も確認する。落ちたら failed。
4. 結果を書き戻す:
   - 成功 → `status: passed`、`evidence:` にコマンドと日時、`## TDD の証拠` に red / green。`bash scripts/run-log.sh done <id> passed <秒数>`。
   - 失敗 → `attempts` +1、`status: failed`、**`## 試行ログ` に 1 件追記する**。追記には実行したコマンド、exit、`error_verbatim` を **原文のまま** (要約も切り詰めもしない)、試したこと、仮説を含める。`run-log.sh done <id> failed <秒数>`。
   - 同時に `knowledge/failures.jsonl` に 1 行追記する (学習ループの元データ)。形式は `/mule-learn` を参照。
5. `attempts` が 3 に達したら `status: blocked` にし、**試行ログ全体を添えて** 人に報告して止まる。原因が仕様の曖昧さなら `/mule-start` に戻ることを勧める。
6. 取り出せるゴールが無くなるまで 1 に戻る。

## 全ゴールが passed になったら
1. `mvn -q clean test` を全体で 1 回流す (ゴール単位では絞り込んでいたため)。
2. `bash scripts/coverage-check.sh` で全 flow が覆われているか確認する。
3. `mule-reviewer` を起動し、`bash scripts/run-log.sh review <verdict> <指摘数>` を記録する。`request-changes` なら指摘をゴールに変換して台帳に追加し、ループへ戻る。
4. `bash scripts/metrics.sh` の表を人に見せる。
5. `approve` ならコミットし、`gh pr create` で PR を作る。**マージは人 (ゲート 2)。**

## デプロイ
`context/deployment/authorizations.yaml` の `deploy.sandbox` が `allowed` で、**かつ人がこの会話で明示的に指示した場合のみ**、Sandbox 型の環境にデプロイしてよい。`production` は常に人が手で行う。ファイルが `denied` なら、人が口頭で許可してもデプロイしない (ファイルを直すのは人)。

## 禁止
- テストや samples の期待値を変えて通すこと。
- `done_when` の無いゴールを実行すること。
- 予算超過後に配ること。
