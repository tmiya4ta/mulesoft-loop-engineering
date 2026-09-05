# MuleSoft API のループエンジニアリング

## 考え方

「仕様を書く、生成する、機械的に検証する、直す」を Claude Code に回させ、人は **仕様・検証器・最終判断** だけを持つ。
ループは役割ではなく **「何に対して閉じるか (判定者)」** で分ける。すると 3 つに収まる。

| ループ | 回す主体 | 判定者 | 出力 | 同期/非同期 |
|---|---|---|---|---|
| 意図ループ | 人 + 進捗エージェント (`/mule-start` 手順 1〜3) | **人** | RAML 差分、サンプルのペア、MUnit 雛形 | 同期 |
| 計画ループ | 進捗エージェント (`/mule-start` 手順 4、`/mule-run`) | **受け入れ条件** | `tasks/T-*.md` (done_when つき) | 非同期 |
| 実行ループ | 実行エージェント (`mule-executor`) | **done_when** | コードと証拠 | 非同期 |

```
  人 ──┐
       │  意図ループ                        判定者 = 人
       ▼
  RAML + samples + MUnit 雛形 ──┐
                                │  計画ループ                 判定者 = 受け入れテスト
                                ▼
                        tasks/T-*.md (done_when) ──┐
                                                    │  実行ループ   判定者 = done_when
                                                    ▼
                                                コード + 証拠
       ▲                 ▲                         │
       └── 仕様が曖昧 ───┴──── 3 回失敗 ────────────┘   失敗は上に昇る
```

**ゴールは下に降り、失敗は上に昇る。** 実行が 3 周直らなければ計画に、計画で分解できなければ仕様に、仕様で決められなければ人に返る。

## 実行ループは TDD で回す

実行ループの中身は Red → Green → Refactor に固定する (`skills/mule-tdd`)。

| 段階 | やること | 証拠 |
|---|---|---|
| Red | samples のペアから MUnit を書き、`mvn -q test -Dmunit.test=X` が **失敗する** ことを確認 | exit 1 |
| Green | 失敗しているテスト 1 つを通す最小の実装 | exit 0 |
| Refactor | 通ったまま整える。1 手ごとにテスト | exit 0 のまま |

なぜ TDD か。ループエンジニアリングでは「何をもって終わりか」が全てで、TDD は終了条件をコードより先に書く規律そのもの。Red を確認しないテストは何も判定していないので、進捗エージェントは red の証拠が無い diff を受け取らない。

意図ループの手順 3 で作る MUnit は雛形ではなく本物のテストで、承認時点で Red になっている。つまり **人が承認するのは「失敗しているテスト」** で、実行ループの仕事はそれを Green にすることだけ。

## 3 つの規則

1. **done_when の無いゴールは存在しない。** hook が弾く。
2. **期待値は変えない。** samples/ と MUnit の期待値を変えて通すのは禁止。実行エージェントがやったら diff を捨てる。
3. **人のゲートは 3 つだけ。** 受け入れ条件の承認、PR のマージ、本番デプロイ。

## 検証器は 3 段

| 段 | 検証器 | 目安 | 担当 |
|---|---|---|---|
| 1 | xmllint、`dw` CLI、層の越境 grep、done_when 有無 | 秒 | hook (`scripts/quick-check.sh`) が自動 |
| 2 | `mvn -q test -Dmunit.test=<対象ファイル>`、mulex | 十秒 | 実行エージェント |
| 3 | `mvn -q test` 全体、契約テスト | 分 | 進捗エージェント (`done_when`) と CI |

ループ 1 周が 1 分を超えると人がループを待たずに手で直し始める。段 1 と 2 を速く保つことが採用率を決める。

## エージェント構成

進捗エージェントは **コマンドを打ったメインセッション自身**。サブエージェントは入れ子にできないので、台帳を持って配る役はメインが担う。

| 名前 | 形 | 判定者 | 書ける |
|---|---|---|---|
| 進捗 | `/mule-start` `/mule-run` を実行中のメインセッション | 人 / 受け入れ条件 | 台帳、仕様、用語集 |
| 実行 | `agents/mule-executor.md` (worktree 隔離) | done_when | src/ のみ |
| レビュー | `agents/mule-reviewer.md` | 規約 | 書けない |

意図ループの深掘りは自作せず、`mattpocock-skills` の `grilling` (決定の木を 1 ラウンドずつ、推奨回答つき) と `domain-modeling` (用語集を即時更新) を借りる。自前部分は「初心者向けの前置き 3 問」と「MuleSoft 固有の出口 (RAML / samples / MUnit)」だけ。

## MuleSoft 公式ツールの位置づけ

詳細は [mulesoft-tools.md](mulesoft-tools.md)。原則は **公式ツールは生成を速くし、mule-loop は判定を握る**。

| ループ | 借りるもの |
|---|---|
| 意図 | `platform-assistant` (同梱) で既存 API を調べる。MCP `generate_api_spec` で RAML 草稿。`api-spec-validator` で検証 |
| 実行 (Green) | 公式スキル `build-mule-integration`、MCP `generate_mule_flow`。出力は仮説で MUnit が判定 |
| 段 3 | 公式スキル `generate-bat-tests` (デプロイ後の契約テスト) |
| ゲート 3 の後 | MCP `deploy_mule_application`、Platform MCP と `secure-api` でポリシー |
| 維持 | MCP `get_platform_insights`、Platform MCP のモニタリング |

## チームへの展開

1. **パイロット** (2 週間、1〜2 名、System API 1 本): 成果物は API ではなくこのテンプレートの調整。
2. **テンプレート化**: `/mule-init` で配れる形にする (このリポジトリ)。
3. **横展開**: 新規 API は全て `/mule-init` から。既存 API は触った時に移行。
4. **維持**: skills と CLAUDE.md の変更は PR レビュー対象。3 周以上回って直らなかったケースを週次で集め、CLAUDE.md か skill を直す担当を 1 名置く。

指標は 4 つで十分: ループ 1 周の時間、初回で done_when を通る率、レビュー差し戻し回数、MUnit カバレッジ。

## 落とし穴

- **Studio 依存**: GUI 操作は Claude Code に渡せない。ただし `/mule-start` の流れなら XML を見る場面が無い。Studio の保存時整形は hook と衝突するので切る。
- **DataWeave**: 静的検査が弱い。サンプルのペアを仕様の一部として先に作らせないと担保できない。
- **認証情報**: Anypoint の Connected App をコンテキストに載せない。deploy は permissions で deny。
- **層の越境**: Claude Code は Process から DB を平気で叩く。CLAUDE.md の禁止と段 1 の grep で機械的に弾く。
