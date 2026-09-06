---
name: mule-status
description: 今どこにいて次に何をすればよいかを示す。迷ったらいつでも呼ぶ。前提、台帳、予算、PR の状態を読み、次の一手を 1 つだけ具体的に提示する。
---

進捗管理の役目は「進み具合を記録すること」ではなく **「次に何をすればよいかを人が迷わない状態に保つこと」** です。

## 読むもの

1. `context/sources.yaml` — 前提が埋まっているか
2. `tasks/T-*.md` — todo / running / failed / blocked / passed の数
3. `knowledge/run-log.jsonl` と `budget.yaml` — 残予算 (`bash scripts/budget-check.sh`)
4. `git status` と `git log --oneline -3`、`gh pr list --head $(git branch --show-current)` — PR の有無と状態
5. `knowledge/failures.jsonl` — 2 回以上の指紋があるか

## 出す形 (必ずこの 3 ブロック)

```
## 現在地
<1 行。何がどこまで終わっているか>

## 次にすること
<1 つだけ。コマンドはそのまま貼れる形で書く。人が判断する場合は選択肢を 2〜3 個>

## そのあと
<それが終わると何が起きるか 1 行>
```

**次にすることは 1 つに絞る。** 複数並べると人はまた迷います。

**人が選ぶものには必ず連番を振る。** `-` の箇条書きでは「2 番をやって」と指定できません。
選択肢、残っているゴール、blocked の一覧、レビューの指摘、昇格候補、人に置いてもらう資料 —
選ぶ可能性があるものは全て `1.` `2.` `3.` にします。台帳の表は `id` (T-001) で指定できるので表のままで構いません。

## 状態から次の一手を決める表

| 状態 | 次にすること |
|---|---|
| `context/sources.yaml` の requirements が空 | 資料を `context/requirements/` に置くか URL を伝える。置き場所のパスを具体的に示す |
| 台帳が無い | `/mule-start <作りたいこと>` |
| todo / failed のゴールがある | `/mule-run` |
| blocked のゴールがある | 試行ログの要点を 3 行で示し、`/mule-start` で仕様に戻るか、人が手で直すかを聞く |
| 予算超過 | 残りのゴールを示し、`budget.yaml` を上げるか、ここで打ち切るかを聞く |
| 全 passed、PR 未作成 | `gh pr create` (コマンドをそのまま出す) |
| **PR 作成済み** | 下の「PR の後」へ |
| 2 回以上の失敗指紋がある | `/mule-learn` |
| 何も残っていない | 次に作る API を聞く。無ければ `bash scripts/metrics.sh` の結果を見せて締める |

## PR の後 (ここで人が迷いやすい)

PR を作ったら **必ず次の 3 つを順に示す**。URL を貼って終わりにしない。

```
## 現在地
T-001〜T-005 が全て passed。レビューは approve。PR #12 を作成しました。
https://github.com/<org>/<repo>/pull/12

## 次にすること
PR をレビューしてマージしてください (人のゲート 2)。
  1. gh pr view 12 --web        # ブラウザで開く
  2. gh pr merge 12 --squash    # 問題なければマージ

## そのあと
マージしたら、私に「マージした」と言ってください。
Sandbox へのデプロイ (authorizations.yaml で許可済みなら) か、
次の機能の /mule-start か、/mule-learn のどれに進むかを案内します。
```

マージ後に呼ばれたら、次はこの順で聞く。

1. `context/deployment/authorizations.yaml` の `deploy.sandbox` が `allowed` なら「Sandbox にデプロイしますか」
2. `knowledge/failures.jsonl` に 2 回以上の指紋があれば「`/mule-learn` で改善しますか」
3. どちらも無ければ「次に作る API はありますか」

複数該当するときは番号付きで並べ、「1 番をやって」と言えるようにする。

## 禁止

- 「以上です」「完了しました」だけで終わること。**必ず次の一手を書く。**
- 次にすることを 3 つ以上並べること。
- 人が選ぶものを `-` の箇条書きで出すこと (番号で指定できない)。
- 人が何をすればよいか分からない終わり方 (URL だけ、表だけ、結果だけ)。
