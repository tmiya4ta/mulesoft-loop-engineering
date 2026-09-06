---
name: mule-tdd
description: MuleSoft の実装を TDD (Red → Green → Refactor) で進める規律。samples/ のペアから MUnit を先に書いて失敗を確認し、通る最小の実装をし、通ったまま整える。ゴール 1 件を実装するとき、実行エージェントが必ず従う。
---

# Mule TDD

ゴール (tasks/T-NNN.md) を受け取ったら、次の順で **しか** 進めない。順を飛ばしたら最初からやり直す。

## 0. 受け入れ条件を確認する
- `samples/<resource>/<case>.in.json` と `.out.json` を全部読む。これが期待値で、**変えない**。
- `api/*.raml` の該当リソース、ステータスコード、スキーマを読む。
- 既存の MUnit (`src/test/munit/`) の書き方に合わせる。

## 1. Red: 失敗するテストを先に書く
- `src/test/munit/<resource>-test.xml` に、samples のケースごとに 1 つ `munit:test` を書く。
  - `munit:behavior` で外部呼び出し (`http:request`, `db:select`, `sap:*` など) を `mock-when` で固定する。返す値は samples の in から導く。
  - `munit:execution` で対象フローを `flow-ref` する。
  - `munit:validation` で `.out.json` と `payload` を `MunitTools::equalTo` か `MunitTools::withMediaType` で比較する。HTTP ステータスも `attributes.statusCode` で確認する。
- **カバレッジは 100% を目標にする。** 具体的には、追加した `flow` / `sub-flow` が 1 つ残らずどれかの `munit:test` から `flow-ref` されること。
  **`coverage-check.sh` が見るのは flow に到達したかだけで、flow の中の分岐は見ない。** `choice` の各分岐、`try` の成功と失敗、`error-handler` の各 error-type は、samples のケースを増やして 1 つずつ通す。ここは機械が保証しないので、テストを書く側が数える。エラーハンドラの分岐も `mock-when` で例外を投げさせて通す。判定は `bash scripts/coverage-check.sh` (exit 0 が条件)。
  MUnit 本来のカバレッジ率計測は Enterprise ランタイム限定で、CE では設定しても警告が出るだけで素通りする。`scripts/munit-coverage-mode.sh` が EE を取得できるときだけ 100% ゲートを pom に入れる。EE が無い環境ではこの構造チェックが唯一の保証になる。
- DataWeave の変換が主題なら、まず `dw` CLI で `.in.json` を流して `.out.json` と diff する簡易テストを作る (秒で回る)。
- **`mvn -q clean test -Dmunit.test=<resource>-test.xml` を実行し、失敗を確認する。** `clean` は必ず付ける (古い成果物のまま素通りするのを防ぐ)。 失敗しないテストは何も検証していない。失敗の理由が「フローが無い」「変換が無い」であることを確かめてから次へ。

## 2. Green: 通る最小の実装をする
- 失敗しているテスト 1 つを通すための最小限だけ書く。先回りして他のリソースやエラー処理を書かない。
- フローは `src/main/mule/<resource>.xml`、変換は `src/main/resources/dwl/<name>.dwl` に置く。インライン DataWeave は書かない。
- 実行順は速い順: `dw` で変換単体 → `mvn -q test -Dmunit.test=<resource>-test.xml`。
- 通ったら次のテスト (失敗ケース、境界ケース) へ。テストごとに Red → Green を繰り返す。

## 3. Refactor: 通ったまま整える
- 重複した変換の共通化、`global.xml` の共通エラーハンドラへの寄せ、命名を CONTEXT.md に合わせる。
- 1 手直すごとに `mvn -q test -Dmunit.test=<resource>-test.xml` を回す。赤くなったら戻す。
- 最後に `done_when` を実行し exit 0 を確認する。

## 禁止
- テストや samples の期待値を実装に合わせて変えること。期待値が間違っていると確信したら **止まって** 理由を報告する。
- Red を確認せずに実装から書き始めること。
- `mock-when` を使わず実際の外部システムに繋ぐこと (MUnit は常に隔離)。

## 出力のたびに残す証拠
```
red:      mvn -q clean test -Dmunit.test=order-cancel-test.xml → exit 1 (期待どおり失敗)
green:    mvn -q clean test -Dmunit.test=order-cancel-test.xml → exit 0
coverage: bash scripts/coverage-check.sh → flow coverage: 4/4 (100%)
done:     <done_when> → exit 0
```
red と green は **同じコマンド** であること。違うコマンドを並べても TDD の証拠にならない。
