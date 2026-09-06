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
1. `tasks/T-*.md` を読み、`status` が `todo` または `failed` (attempts < 3) で、`blocked_by` が全て `passed` のものを取り出す。`stage` が無ければ `impl`。
2. 各ゴールについて:
   - `status: running` に更新する。
   - **モデルを選ぶ。** attempts 0〜1 は `sonnet`、attempts 2 (= 3 回目の挑戦) は `opus` に上げる。Agent 呼び出し時の `model` で指定する (frontmatter より呼び出し側が優先)。
   - `bash scripts/run-log.sh dispatch <id> <model>` を実行する。
   - **段で配り先を変える。回し方は同じ (done_when が exit 0 になるまで)。**
     - `impl` → Agent ツールで `mule-executor` を **`isolation: "worktree"`** で起動する。プロンプトはゴールファイルのパスと「CLAUDE.md と context/ を読んで規則に従うこと」だけ。
     - `deploy` → 実行エージェントには配れない (デプロイ禁止)。**進捗エージェント自身が `mule-deploy` スキルの手順 1〜5 を実行する。** 先に done_when を 1 回流して失敗を確認する (red)。配置先 URL が決まったら done_when の base-url を書き換えてよい (期待値ではなく所在なので)。
     - `policy` → `authorizations.yaml` の `policy.sandbox` が allowed のときだけ `mule-executor` に配る (worktree 不要、`isolation` 無し)。denied なら blocked にして人に 1 行で伝える。
   - **マニュアルは読まない。** 段を進めるのに足りない事実 (CLI の書式、ポリシー名、API インスタンスの id) は、進捗エージェントが docs を fetch して探すのではなく、実行エージェントに「調べて `knowledge/K-NNN.md` に書いてから使う」よう配る。進捗エージェントが読むのは台帳、context/、knowledge/ だけ。
   - 配るたびに budget-check を再実行する (並列時も 1 件ごとに数える)。
3. 戻ってきたら diff を取り込み、**`done_when` を自分で実行する**。実行エージェントの自己申告は信じない。
   - `samples/` か `src/test/munit/` の期待値が変更されていたら、**diff を捨てて failed にする**。理由を試行ログに書く。
   - `red` の証拠が無い、または `red` と `green` が別コマンドなら failed にする (deploy / policy 段も同じ。red は着手前の done_when、green は着手後の done_when)。
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
このループではデプロイしない。マージ後に `/mule-deploy` が担う (ゲートは `context/deployment/authorizations.yaml` の `deploy.sandbox: allowed` と、人がこの会話で明示的に指示すること。`production` は常に人が手で行う)。

## 禁止
- テストや samples の期待値を変えて通すこと。
- `done_when` の無いゴールを実行すること。
- 予算超過後に配ること。
- **次の一手を示さずに終わること。**

---

## 止まるときは必ずナビゲートする (進捗エージェントの本分)

**どんな理由で止まるときも、応答の最後を必ずこの 3 ブロックで締める。** 結果だけ、表だけ、URL だけで終わらない。

```
## 現在地
<1 行>

## 次にすること
<1 つだけ。コマンドはそのまま貼れる形で>

## そのあと
<それが終わると何が起きるか 1 行>
```

次にすることは **1 つに絞る**。複数並べると人はまた迷う。人が選ぶ場面だけ選択肢を 2〜3 個出す。
状態ごとの次の一手は `mule-status` スキルの表に従う。迷ったら Skill ツールで `mule-status` を呼ぶ。

### 一覧には必ず連番を振る

人が選ぶ可能性のあるものは、`-` の箇条書きではなく **`1.` `2.` `3.` の連番** で出す。
番号が無いと「2 番をやって」と指定できない。対象は次のもの全て。

1. 次にすることの選択肢
2. 残っているゴール、blocked のゴール
3. レビューの指摘
4. `/mule-learn` の昇格候補
5. 人に置いてもらう資料や決めてもらう項目

台帳の表は `id` (T-001) がそのまま指定に使えるので、そちらは表のままでよい。


