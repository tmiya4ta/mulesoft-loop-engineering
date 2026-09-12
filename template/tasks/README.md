# tasks/ — ゴール台帳

1 ファイル 1 ゴール。`/mule-start` が切り、`/mule-run` が回す。人が直接編集してもよい。

| status | 意味 |
|---|---|
| todo | 未着手 |
| running | 実行エージェントに配布中 |
| passed | done_when が exit 0 (進捗エージェントが自分で確認) |
| failed | 失敗。attempts < 3 なら再試行される |
| blocked | 3 回失敗。人の判断待ち |

`done_when` の無いファイルは hook が弾く。

## 段 (stage) — 実装の先も台帳の中で回す

ループが回るのは done_when があるところだけ。デプロイやポリシーを台帳の外でやると、判定者を失って「マニュアルを読んで人に聞く」通常のチャットに戻る。
だから **全段をゴールにする**。`/mule-start` が計画時に impl と一緒に切る。

| stage | 誰が動くか | done_when の例 |
|---|---|---|
| impl | 実行エージェント (TDD) | `mvn -q clean test -Dmunit.test=order-test.xml` |
| deploy | 進捗エージェント (`/mule-deploy` の手順) | `python3 scripts/smoke-check.py https://<app>/api` |
| policy | 実行エージェント (API Manager の CLI) | `bash scripts/policy-check.sh https://<app>/api client-id` |

deploy は全 impl を `blocked_by` にし、policy は deploy を `blocked_by` にする。
done_when が書けない段は、まだ何を確かめるか決まっていないので切らない。
