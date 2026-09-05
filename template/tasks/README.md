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
