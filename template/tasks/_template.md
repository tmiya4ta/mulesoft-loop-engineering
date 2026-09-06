---
id: T-000
goal: <1 文。何ができるようになるか>
stage: impl            # impl | deploy | policy。段が違っても回し方は同じ (done_when が exit 0 になるまで)
done_when: mvn -q clean test -Dmunit.test=<resource>-test.xml
status: todo
attempts: 0
blocked_by: []
evidence: ""
---

## 受け入れ条件
- samples/<resource>/<case>.in.json → .out.json (正常 1 件以上、失敗 1 件以上)
- api/<name>.raml の該当リソース
- このゴールで追加する flow は全て MUnit から flow-ref される (scripts/coverage-check.sh)

## TDD の証拠
- red:
- green:

## 試行ログ
<!-- 失敗するたび進捗エージェントが 1 件追記する。エラーは要約せず原文のまま。
     昇格先のループが同じ調査を繰り返さないための唯一の資産。 -->
<!--
### 試行 1 (2026-09-06T10:00Z, sonnet)
- 実行: mvn -q clean test -Dmunit.test=order-cancel-test.xml
- exit: 1
- 原文:
  ```
  <エラー出力をそのまま貼る。切り詰めない>
  ```
- 何を試したか: <1 行>
- 仮説: <なぜ落ちたと思うか。1 行>
-->

## 補足
<実行エージェントに渡したい文脈があれば。無ければ空>
