---
name: mule-learn
description: 学習ループ。実装で繰り返した失敗を数え、2 回以上出た指紋を hook / 規則 / レビュー観点に昇格させ、汎用のものはプラグインへ PR して共有する。週次か、ゴールが blocked になったときに使う。
argument-hint: "[--share 汎用ナレッジをプラグインに PR する]"
---

## 元データ

`knowledge/failures.jsonl` — 実行ループで **失敗が直った瞬間に** 1 行追記される。書くのは進捗エージェントで、人は書かない。

```json
{"ts":"2026-09-06","task":"T-014","category":"munit-mock-missing","symptom":"http:request が実サーバーに接続しにいった","fix":"munit:behavior に mock-when を追加","scope":"generic"}
```

`category` は **固定語彙** から選ぶ。自由記述にすると同じ間違いが別の言葉になって数えられない。

| category | 意味 |
|---|---|
| `dataweave-null` | null 安全でないアクセス、暗黙変換 |
| `munit-mock-missing` | mock-when 漏れで実システムに接続 |
| `munit-coverage` | flow がテストから参照されていない |
| `raml-mismatch` | RAML と実装のずれ |
| `connector-version` | GAV の推測、版の不一致 |
| `layer-violation` | 層の越境 |
| `xml-namespace` | XSD / 名前空間の不足 |
| `error-handler` | エラーハンドラ漏れ、握りつぶし |
| `build-config` | pom / mule-artifact.json の設定 |

`scope` は `repo` (このリポジトリ固有) か `generic` (どの Mule プロジェクトでも起きる)。

## 手順

1. **数える。** `knowledge/failures.jsonl` を category と symptom の組で集計し、**2 回以上のものだけ** を候補にする。1 回はただの事故で、規則を増やすと CLAUDE.md が肥大して読まれなくなる。
2. **昇格先を選ぶ。** 低い層から順に検討し、**機械で弾けるなら必ず hook にする**。規則は読まれないことがあるが hook は必ず効く。

   | 順 | 昇格先 | 条件 |
   |---|---|---|
   | 1 | `scripts/quick-check.sh` の検査 | grep や XML 解析で機械的に判定できる |
   | 2 | `CLAUDE.md` か `mule-tdd` の規則 | 判定はできないが、書けば守れる |
   | 3 | `mule-reviewer` の観点 | 文脈依存で、人の目に近い判断が要る |

3. **書く。** `knowledge/K-NNN.md` に症状、原因、直し方、昇格先、根拠になった失敗の件数と task id を残す。
4. **hook に昇格したものはテストを付ける。** それを踏む最小の入力を `knowledge/fixtures/` に置き、quick-check が exit 2 で弾くことを確認する。弾けないなら昇格していない。
5. **PR にする。** 昇格は必ず PR にして人がマージする (**追加のゲートはこれ 1 つだけ**)。エージェントが直接 CLAUDE.md を書き換えない。
6. **退役させる。** 半年ヒットが無い規則は削除を提案する。増える一方の規則は死んだ規則になる。

## `--share` — チームで共有する

`scope: generic` のナレッジは、このリポジトリに閉じ込めず **プラグイン側の `knowledge/gotchas.md`** に PR する。実行エージェントは毎回それを読むので、マージした時点で全リポジトリ・全メンバーに効く。

```bash
gh repo clone tmiya4ta/mulesoft-loop-engineering /tmp/ml && cd /tmp/ml
git switch -c learn/<category>-<短い名前>
# knowledge/gotchas.md に追記 (症状 / 原因 / 直し方 / 根拠の件数)
gh pr create --title "gotcha: <symptom>" --body "<根拠: どのリポジトリで何回>"
```

別のプロジェクトから同じ指紋の PR が来たら、それ自体が強い証拠になる。PR の本文に必ず件数とリポジトリ名を書く。

`scope: repo` のものはそのリポジトリの `knowledge/` に留める。共有しても他所では役に立たず、ノイズになる。

## 使わないもの

Claude Code の auto-memory には書かない。個人の `~/.claude` に溜まって共有されず、PR レビューも通らない。ナレッジは必ずリポジトリ内のファイルに置く。
