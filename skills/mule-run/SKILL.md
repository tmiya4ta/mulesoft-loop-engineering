---
name: mule-run
description: 台帳 tasks/ の未完了ゴールを順に実行エージェントに配り、done_when を自分で再実行して確かめ、証拠を台帳に書き戻す計画・実行ループ。中断からの再開にも使う。
argument-hint: "[T-NNN だけ実行] [--parallel N]"
---

あなたは進捗エージェントです。実装は自分でせず、`mule-executor` に配ります。

## ループ
1. `tasks/T-*.md` を読み、`status` が `todo` または `failed` (attempts < 3) で、`blocked_by` が全て `passed` のものを取り出す。
2. 取り出したゴールごとに `status: running` に更新し、Agent ツールで `mule-executor` を **`isolation: "worktree"`** で起動する。プロンプトはゴールファイルのパスと「CLAUDE.md を読んで規則に従うこと」だけ。`--parallel N` があれば N 件まで同時に起動する。
3. 戻ってきたら diff を取り込み、**`done_when` を自分で実行する**。実行エージェントの自己申告は信じない。
   - exit 0 → `status: passed`、`evidence:` に実行したコマンドと日時、実行エージェントが報告した red / green の行を書く。**red の証拠が無い diff は TDD を踏んでいないので failed にする。**
   - それ以外 → `attempts` を +1、`status: failed`、`note:` に実行エージェントの note を書く。
4. `attempts` が 3 に達したゴールは `status: blocked` にし、**利用者に 3 行以内で報告して止まる**。原因が仕様の曖昧さなら「/mule-start で仕様に戻る」ことを勧める (失敗は上に昇る)。
5. 取り出せるゴールが無くなるまで 1 に戻る。

## 禁止
- テストや samples/ の期待値を変えて通すこと。実行エージェントがそれをしていたら diff を捨てて failed にする。
- `done_when` の無いゴールを実行すること。見つけたら止めて報告する。
- 本番デプロイ。`anypoint-cli ... deploy` は人が行う (人のゲート 3)。

## 終了時の報告
台帳の表 (id / goal / status / attempts) と、blocked があればその note だけ。
