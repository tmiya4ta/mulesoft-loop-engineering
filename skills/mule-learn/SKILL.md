---
name: mule-learn
description: 学習ループ。実装で繰り返した失敗を数え、2 回以上出た指紋を hook / 規則 / レビュー観点に昇格させ、汎用のものはプラグインへ PR して共有する。週次か、ゴールが blocked になったときに使う。
argument-hint: "[--share 汎用ナレッジをプラグインに PR する]"
---

## 元データ

`knowledge/failures.jsonl` — 実行ループとデプロイのループ (`/mule-deploy`) で **失敗が直った瞬間に** 1 行追記される。ゴールが一発で通ったときも、実行エージェントの報告の `learned` から進捗エージェントが書く。書くのは進捗エージェントで、人は書かない。

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
| `deploy-config` | デプロイ設定 (groupId、target、vCores、Exchange 認証) の誤り |
| `deploy-runtime` | 配置先で起動しない (FAILED、properties 不足、Java 版) |
| `deploy-connectivity` | MUnit では mock で隠れていた接続先の不一致 (smoke-check の mismatch) |
| `connector-behavior` | コネクタや DB の戻り値の意味を誤解した (affectedRows、target= と mock、MIME の自動解釈) |
| `loop-ops` | ループ自体の運用 (worktree、K ファイルの衝突、hook の誤検知)。昇格先はプラグインへの PR |
| `test-toothless` | 検証しているつもりで何も検証していないテストや検査 (default 付き assert、走っていない検査、手書きの期待値) |
| `secret-leak` | 資格情報を追跡ファイルやログに書きかけた |
| `environment-fact` | 実接続して初めて分かった接続先やドライバの事実 (現在スキーマ、SQLSTATE が常に null、型の着地)。**昇格先は `knowledge/gotchas/` ではなく `context/environment/`** — この接続先でしか成り立たず、他プロジェクトに持ち出すと嘘になる |
| `other` | 上のどれにも当てはまらない。**この値が付いていること自体が「語彙が足りない」という信号** |

**表に無い言葉を作らない。** 当てはまるものが無ければ必ず `other` を使う。自作の値は集計で別物として
扱われ、数えられず昇格もされない。実例として finance-api には `uncategorized` という自作の値が 13 件
溜まり、その中には**この後 2 回踏むことになるループのバグ (worktree の基点が古い件、v0.6.4 で修正)** が
入っていたが、一度も昇格されなかった。

`scope` は `repo` (このリポジトリ固有) か `generic` (どの Mule プロジェクトでも起きる)。

## 手順

0. **`other` と、語彙に無い値を先に片付ける。** 件数に関わらず**毎回**読み直し、今の語彙のどれかに分類し直す。
   どれにも入らないなら語彙そのものを増やす提案をする (それが `other` の役目)。
   **語彙を増やしたときは、過去の `other` を必ず読み直す。** 増えた語彙は過去に遡って適用されないので、
   ここをやらないと「記録はされたが分類されず、分類されないから昇格されない」行が溜まり続ける。
   これは分類のやり直しであって昇格ではない。昇格するかは分類した後に下の 2 回ルールで判定する。
   **分類し直すと順位が変わる。** 実例: finance-api の 41 件のうち 18 件が語彙外 (`uncategorized` 13、
   `toothless-assertion` 4、`connector-usage` 1) で、2 プロジェクト合算の 1 位は `munit-coverage` 8 に
   見えていた。分類し直すと **`loop-ops` が 4 → 10 で 1 位**になった (語彙外の 6 件が worktree の基点、
   K ファイルの衝突、台帳が書かれない、配布の分担破りだった)。**順位が変わるので、数える前に必ず
   手順 0 をやる。** 昇格先も変わる (`loop-ops` の行き先はプラグイン本体への PR)。
1. **数える。** `knowledge/failures.jsonl` を category と**原因**の組で集計する。
   **symptom の文字列一致で数えない。** 同じ原因が別の言葉で書かれていたら 1 つの指紋としてまとめる。
   実例: worktree の基点が古い件は「`tasks/T-NNN.md` が存在しなかった」と「依存ゴールの成果が無かった」で
   別々に記録され、原因は同じなのに 1 回ずつと数えられていた。

   **何回で昇格するかは、回数ではなく昇格先で決める。**

   | 昇格先 | 必要な回数 | 理由 |
   |---|---|---|
   | hook / script / 写経元 (`template/reference/`) | **1 回** | 読む負担がゼロ。効く場所に置くだけで、増えても誰も遅くならない |
   | 文章の規則 (`CLAUDE.md`、スキル、`mule-reviewer` の観点) | **2 回** | 読む負担がある。1 回の事故で増やすと肥大して読まれなくなる |

   **1 回でも機械で弾けるなら、その場で弾く。** 「まだ 1 回だから」を機械化しない理由にしない。
   実例: 進捗エージェントが自分で宣言した分担を破った件は 1 回だったため規則に留め (v0.6.13)、
   同じ判断で放置されるところだった。2 回目を待つのは**文章にしかできないとき**だけ。
   逆に、2 回以上出ていても**機械で弾けないなら文章**にする (それは負担を払う価値がある)。

   回数が足りなくても、**同じ形で 3 回以上解決しているものは写経元にする** (手順 2 の表を参照)。
   これは「規則を増やす」ではなく「写す元を置く」なので、読む負担が増えません。
2. **昇格先を選ぶ。** 低い層から順に検討し、**機械で弾けるなら必ず hook か script にする**。規則は読まれないことがあるが hook は必ず効く。**機械にできるかを先に考える** (できるなら 1 回で昇格できる)。

   | 順 | 昇格先 | 条件 |
   |---|---|---|
   | 1 | `scripts/quick-check.py` の検査 | grep や XML 解析で機械的に判定できる |
   | 2 | **主題別スキル** (`skills/mule-munit/` など) と、必要なら `template/reference/` の写経元 | 判定はできないが、書き方を示せば守れる |
   | 3 | `CLAUDE.md` か `mule-tdd` の規則 | どの主題にも属さない横断的な規律 |
   | 4 | `mule-reviewer` の観点 | 文脈依存で、人の目に近い判断が要る |

   **主題別スキルへの追記先は category で決める** (指紋がどこにも溜まらなくなるのを防ぐため)。

   | category | 追記先 |
   |---|---|
   | `munit-*` / `test-toothless` | `skills/mule-munit/SKILL.md` |
   | `environment-fact` | **このリポジトリの `context/environment/`** (プラグインには持ち出さない) |
   | `loop-ops` | プラグイン本体への PR (下記) |
   | それ以外 | `knowledge/gotchas/<主題>.md` — 主題は `knowledge/gotchas.md` の索引の表から選ぶ。**合う主題が無ければ新しいファイルを作り、索引の表に 1 行足す** |

   **`knowledge/gotchas/` への追記はやめない。** そこは根拠と日付つきの一次記録で、スキルはそこから
   「順番」と「写経元の在処」だけを抜いた薄い層です。両方に書く。
   **追記したら `knowledge/gotchas.md` の索引の件数と症状の欄も直し、`bash scripts/knowledge-index-check.sh`
   を通す (exit 0 が条件)。** 索引が実体とずれると、読む側は「合う行が無い」と判断してそのファイルを
   開かなくなり、書いた項目が誰にも読まれません。**これは文章で守らせません** — 手で持つ数字は
   ずれます (PR #2 が目次を 11 件のまま残し、v0.6.15 は索引の行数を全部 1 ずつ間違えました)。判定は機械。
   **同じ形で 3 回以上解決しているものは、文章ではなく `template/reference/` の写経元にする。**
   実例: APIkit の振り分け flow の直叩きは 6 回とも同じ形で解決できたが、写経元が無いため毎回踏んでいた
   (`reference/router-test.xml` として v0.6.11 で追加)。

   **`loop-ops` だけは行き先が違う。** 上の 3 つは全てこのリポジトリの中で、Mule の書き方の誤りを対象に
   している。ループ自体の運用の誤り (worktree、配布、K ファイルの衝突、hook の誤検知) は、このリポジトリを
   直しても次のプロジェクトで再発する。**プラグイン本体の `skills/` / `hooks/` / `scripts/` を直す PR** を出す。
   `knowledge/gotchas/` への追記では解決しない (手順の欠陥であって、知っていれば避けられる事実ではないため)。

3. **書く。** `bash scripts/k-new.sh learn` が出したパス (`knowledge/K-learn-<連番>.md`) に残す。
   **番号は手で決めない** (並列で同じ番号を選んで衝突した実例がある)。
   中身は実行エージェントの K ファイルと同じ形 — **症状 (原文) / 原因 / 直し方 / 根拠のコマンド /
   どこで調べたか** — に、**昇格の記録に限って** 昇格先、根拠になった失敗の件数、task id を足す。
4. **hook に昇格したものはテストを付ける。** **その hook は今のセッションでは効きません** —
   `hooks.json` はセッション開始時の cache から読まれるので、実際に発火させて確かめることはできません
   (`knowledge/gotchas/build.md`)。**hook の JSON をスクリプトに直接流して**確かめます:
   `printf '{"tool_input":{...}}' | python3 scripts/<hook>.py`。
   **そのケースを `scripts/hooks-check.py` の `EXPECTED` に 1 行足してください** (入力の作り方は
   `cases_for()` に書く)。`python3 scripts/hooks-check.py` が exit 0 になるのが条件で、以後
   hook を直したときにここが落ちます。XML の形の指紋なら、踏む最小の入力を `knowledge/fixtures/` に置き、
   `knowledge/fixtures/README.md` の表に 1 行足して `bash scripts/fixtures-check.sh` を通す (exit 0 が条件)。
   **正しい形が誤検知されないことも同時に確かめます** — `ok-*.xml` を 1 つ足す。deny する hook の誤検知は
   編集を止めるので、弾く側だけ試すのでは足りません (台帳に `dw-validate-false-positive-p` の実例があります)。
   弾けないなら昇格していない。
5. **PR にする。** 昇格は必ず PR にして人がマージする (**追加のゲートはこれ 1 つだけ**)。エージェントが直接 CLAUDE.md を書き換えない。
6. **退役させる。** 半年ヒットが無い規則は削除を提案する。増える一方の規則は死んだ規則になる。

## `--share` — チームで共有する

`scope: generic` のナレッジは、このリポジトリに閉じ込めず **プラグイン側の `knowledge/gotchas/<主題>.md`** に PR する。実行エージェントは詰まったときに索引からそこを開くので、マージした時点で全リポジトリ・全メンバーに効く。

```bash
gh repo clone tmiya4ta/mulesoft-loop-engineering /tmp/ml && cd /tmp/ml
git switch -c learn/<category>-<短い名前>
# knowledge/gotchas/<主題>.md に追記 (症状 / 原因 / 直し方 / 根拠の件数)
# 索引 (knowledge/gotchas.md) の件数と症状の欄も直す
# 「API から取れない」を【未解決】で書くなら、その前に template/scripts/portal-search.py で項目名を
# 3 語引き、引いた語と結果を本文に書く (無ければ knowledge-index-check が弾く)。v0.6.37 の【未解決】は
# 36 本中 2 本の API しか見ておらず、実際は Gateway Manager API の応答に載っていた
# **検査と PR を同じコマンドの && で繋ぐ。** 1 つでも落ちたら PR は開かれない。
# hook (promote-guard) にも同じ検査があるが、hook はセッション開始時の版で固定されるので
# 載っていないことがある (knowledge/gotchas/build.md)。手順だけで止まる形にしておく。
cd /tmp/ml && bash scripts/knowledge-index-check.sh && bash scripts/fixtures-check.sh \
  && bash scripts/checks-audit.sh && python3 scripts/hooks-check.py \
  && gh pr create --title "gotcha: <symptom>" --body "<根拠: どのリポジトリで何回>"
```

別のプロジェクトから同じ指紋の PR が来たら、それ自体が強い証拠になる。PR の本文に必ず件数とリポジトリ名を書く。

`scope: repo` のものはそのリポジトリの `knowledge/` に留める。共有しても他所では役に立たず、ノイズになる。

## 使わないもの

Claude Code の auto-memory には書かない。個人の `~/.claude` に溜まって共有されず、PR レビューも通らない。ナレッジは必ずリポジトリ内のファイルに置く。
