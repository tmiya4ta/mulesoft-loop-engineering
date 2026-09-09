---
name: mule-run
description: 台帳 tasks/ の未完了ゴールを予算内で実行エージェントに配り、done_when を自分で再実行して確かめ、証拠と試行ログを台帳に書き戻す計画・実行ループ。中断からの再開にも使う。
argument-hint: "[T-NNN だけ実行] [--parallel N (既定は予算が許す最大。1 で直列)]"
---

あなたは進捗エージェントです。実装は自分でせず、`mule-executor` に配ります。

## 配る前に必ず 3 つ確認する
1. `bash scripts/budget-check.sh` を実行する。**exit 1 なら 1 件も配らずに止まり**、人に残予算と状況を報告する。出力の `max_parallel` が **既定の同時実行数**。`--parallel N` はこれを **下げる** ときだけ使う (`--parallel 1` で直列)。引数が `max_parallel` を超えていたら切り下げる。
2. `context/sources.yaml` が埋まっているか。`requirements` が空で `note` も空なら、`/mule-start` に戻るよう案内して止まる。
3. ゴールに `done_when` があるか。無ければ止めて報告する。
4. `git rev-parse HEAD` が通るか。コミットが 1 つも無いと worktree が作れない。無ければ `git add -A && git commit -m "mule-loop: init"` を作ってから配る。

## ループ
1. `tasks/T-*.md` を読み、`status` が `todo` または `failed` (attempts < 3) で、`blocked_by` が全て `passed` のものを取り出す。`stage` が無ければ `impl`。
2. **取り出せたゴールは 1 件ずつではなく `max_parallel` 件まで同時に配る。これが既定。**
   `blocked_by` が解けているゴールは互いに独立なので、戻りを待つ理由が無い。
   1 つの応答の中に Agent 呼び出しを並べれば同時に走る (`impl` 段のみ。`deploy` は進捗エージェント自身が順に行う)。
   直列にしたいときだけ `--parallel 1` を渡す。

   **まず `bash scripts/preflight.sh` を実行する。exit 0 でなければ 1 件も配らない。**
   全ゴールが共有する土台 (依存の解決、Java、アプリが固まること) を 1 回だけ確かめる。
   ここが壊れていると **N 体が同じ原因で各 3 回試して全滅する**ので、コスト 1 回で N×3 を止める。
   落ちたときは:
   - **どのゴールも `running` にしない。`attempts` も増やさない** (ゴールの失敗ではなく土台の失敗のため)。
   - `knowledge/failures.jsonl` に 1 行 (`category: build-config`)。
   - preflight の出力を**原文のまま**添えて人に報告し、止まる。土台が直るまで配っても無駄に燃やすだけ。

   preflight は **MUnit を流さない**。実行ループの途中では失敗したゴールの red なテストが木に残っており、
   `mvn test` は設計どおり赤くなる。それで波を止めると毎回 1 件目のゴール失敗で全部止まってしまう。

   **preflight が通ったら、この波の全ゴールを `running` に書き換えたうえで作業ツリーを 1 回コミットする。**
   **順序を逆にしない。** preflight で止まったときに `running` のまま残ると、取り出し条件が
   `todo` / `failed` なので、そのゴールは二度と配られなくなる。
   ```bash
   git add -A && git commit -q -m "mule-loop: dispatch T-003 T-004"
   ```
   `isolation: "worktree"` の worktree は **HEAD から作られ、未コミットの変更は引き継がれない**。
   コミットせずに配ると、実行エージェントの worktree に
   **(a) いま配ろうとしているゴールファイル `tasks/T-NNN.md` そのもの**、
   **(b) 前の波で取り込んだ依存ゴールの成果 (pom.xml、global.xml、`knowledge/K-*.md`、config)** が無い。
   `blocked_by` で依存を表現している意味が消えるので、**依存があるゴールほど確実に踏む**。
   `.gitignore` に `target/` と `.claude/worktrees/` があるので `git add -A` で巻き込まない。
   (finance-api の T-011 と T-012 で 2 回発生し、どちらも「ゴールファイルが無い」「依存ゴールの成果が無い」で落ちた。)

   **monorepo (1 つの git リポジトリの中に複数の Mule プロジェクトが同居する構成) では、コミットしても
   なお worktree の HEAD がセッション開始時点の古いコミットに固定されることがある。** これは上の
   「コミットせずに配った」場合とは別の症状で、`git add -A && git commit` を毎回きちんと実行していても
   起きる。`isolation: "worktree"` の worktree 作成がベースコミットをセッション単位で解決しており、
   Agent 呼び出しのたびには更新されないためと見られる (ツール側の挙動。プラグイン側では直せない)。
   **最初の 1 波を isolation: "worktree" で配ったら、戻ってきた結果に自己検証を仕込んでおく**
   (プロンプトに「最初に `git rev-parse HEAD` と `pwd` を確認し、配布時点の期待 HEAD と不一致なら
   即中断して報告すること」を 1 行足す)。不一致が確認できたら、**以降のゴールは全て isolation を
   使わない直列実行に切り替える** (`mule-executor` を isolation なしで直接作業ツリー上に呼ぶ。同一
   セッション内で 2 回目の worktree を試しても、同じ古いコミットに固定されたままなので意味が無い)。
   直列に落ちると `parallel.max` を無視した速度になるので、それも台帳か報告に書いて予算消費のペースが
   変わることを分かるようにしておく。
   (inventory2-api の T-001 で 2 回発生。1 回目は monorepo 内の別プロジェクトの `tasks/T-001.md` を
   誤編集した (worktree ブランチのみ、main には未マージで実害なし)。2 回目は絶対パス化と自己検証を
   足して再配布したが、worktree の HEAD は 1 回目と全く同じ古いコミットのままだった。)

   ゴールごとにやることは:
   - `status: running` に更新する (上のコミットに含める)。
   - **モデルを選ぶ。** attempts 0〜1 は `sonnet`、attempts 2 (= 3 回目の挑戦) は `opus` に上げる。Agent 呼び出し時の `model` で指定する (frontmatter より呼び出し側が優先)。
   - `bash scripts/run-log.sh dispatch <id> <model>` を実行する。
   - **段で配り先を変える。回し方は同じ (done_when が exit 0 になるまで)。**
     - `impl` → Agent ツールで `mule-executor` を **`isolation: "worktree"`** で起動する。プロンプトはゴールファイルのパスと「CLAUDE.md と context/ を読んで規則に従うこと」だけ。
     - `deploy` → 実行エージェントには配れない (デプロイ禁止)。**進捗エージェント自身が `mule-deploy` スキルの手順 1〜5 を実行する。** 先に done_when を 1 回流して失敗を確認する (red)。配置先 URL が決まったら done_when の base-url を書き換えてよい (期待値ではなく所在なので)。
     - `policy` → `authorizations.yaml` の `policy.sandbox` が allowed のときだけ `mule-executor` に配る (worktree 不要、`isolation` 無し)。denied なら blocked にして人に 1 行で伝える。
   - **マニュアルは読まない。** 段を進めるのに足りない事実 (CLI の書式、ポリシー名、API インスタンスの id) は、進捗エージェントが docs を fetch して探すのではなく、実行エージェントに「gotchas → スキル (platform-assistant) → マニュアルの順で調べて `knowledge/K-<ゴール id>-<連番>.md` に書いてから使う」よう配る。進捗エージェントが読むのは台帳、context/、knowledge/ だけ。
   - **1 波を配り終えたら budget-check を再実行する** (並列でも 1 件ずつ数える)。`remaining_runs` を超える分は次の波に回す。
3. 戻ってきたら diff を取り込み、**`done_when` を自分で実行する**。実行エージェントの自己申告は信じない。
   - **並列の取り込みは 1 件ずつ、取り込むたびに done_when を流す。** 独立なのは順序だけで、ファイルは独立ではない (pom.xml、global.xml、RAML は複数のゴールが触る)。
     取り込みで衝突したら、**その 1 件だけ failed にして** (attempts は +1 しない) 試行ログに衝突したファイルと相手のゴール id を書き、次の波で配り直す。衝突を手で解消しない。
     衝突が同じ組で 2 回続いたら、共通ファイルを触る部分を切り出した下準備ゴールを作り、両方の `blocked_by` にする。
   - `samples/` か `src/test/munit/` の期待値が変更されていたら、**diff を捨てて failed にする**。理由を試行ログに書く。
   - `red` の証拠が無い、または `red` と `green` が別コマンドなら failed にする (deploy / policy 段も同じ。red は着手前の done_when、green は着手後の done_when)。
   - exit 0 → `bash scripts/coverage-check.sh` も確認する。落ちたら failed。
4. 結果を書き戻す:
   - 成功 → `status: passed`、`evidence:` にコマンドと日時、`## TDD の証拠` に red / green。`bash scripts/run-log.sh done <id> passed <秒数>`。**報告の `learned` があれば 1 件ずつ `knowledge/failures.jsonl` に追記する** (成功でも)。`knowledge` に書かれた K ファイルが diff に含まれていることを確認し、無ければ failed にはしないが試行ログに「学びの記録なし」と書く。
   - 失敗 → `attempts` +1、`status: failed`、**`## 試行ログ` に 1 件追記する**。追記には実行したコマンド、exit、`error_verbatim` を **原文のまま** (要約も切り詰めもしない)、試したこと、仮説を含める。`run-log.sh done <id> failed <秒数>`。
   - 同時に `knowledge/failures.jsonl` に 1 行追記する (学習ループの元データ)。形式は `/mule-learn` を参照。
     **`category` は `/mule-learn` の固定語彙から選ぶ。当てはまるものが無ければ `other`。自分で言葉を作らない。**
     自作の値は集計で別物になり、数えられず昇格もされない (`uncategorized` が 13 件溜まった実例がある)。
     ループ自体の運用でつまずいたとき (worktree、配布、K ファイルの衝突、hook の誤検知) は `loop-ops`。
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
- **ゴールが 1 件 passed になるたびに人に確認を取ること。** 台帳に書けば伝わっている。
- **次の一手を示さずに終わること。**

---

## このループで止まってよいのは 5 か所だけ

**進捗の報告先は台帳であって、対話ではない。** ゴールが 1 件 `passed` になったことは
`tasks/T-NNN.md` の `status` と `evidence` に書けば伝わっている。書いたら次のゴールを配る。
人に見せて「次に進んでよいですか」と聞かない。

| 止まる場所 | 条件 |
|---|---|
| ゲート 2 | PR を作ったあとのマージ |
| blocked | `attempts` が 3 に達した (試行ログ全体を添えて報告) |
| 予算超過 | `budget-check.sh` が exit 1 |
| 土台の破損 | `preflight.sh` が exit 0 でない (配る前の共通検査。出力の原文を添えて報告) |
| 段の許可 | `deploy` / `policy` 段で `authorizations.yaml` が denied、または人の明示指示がまだ無い |

ゲート 1 (受け入れ条件の承認) は `/mule-start`、ゲート 4 (昇格 PR) は `/mule-learn` の担当で、
このループには来ない。**上の 5 つ以外では止まらない。** 判断が要る場面でも、`done_when` が
判定できることなら自分で決めて進み、決めた内容と理由を台帳に書く。

実測: System API 1 本で人が答えた 37 回のうち、ゲートに当たるのは 6 回だけだった。
16 回は人の側から出た指示や事実の提供で、**残り 15 回は `ok` `はい` `A` — 進んでよいかの確認だけ**。
この 15 回で 1.5 時間が消えている (`docs/methodology.md` の「実測」)。

---

## 止まるときは必ずナビゲートする (進捗エージェントの本分)

**この節は上の 5 か所で止まったときの書き方であって、止まってよい場所を増やすものではない。**
ナビゲートは締め方の規則であり、締める口実ではない。

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


