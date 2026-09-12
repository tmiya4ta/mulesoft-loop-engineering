---
name: mule-guide
description: 迷ったら最初に開く手引き。エラーが出た、次に何をすればいいか分からない、値が分からない (組織 ID・接続情報・版)、pom に何を足すか、MUnit の書き方、デプロイの順番、人に聞くべきか — を、状況ごとに「次の 1 手」とそのままコピーできるコマンドで示す。Mule を知らなくても順番どおりにやれば進めるように書いてある。
---

# 迷ったときの手引き

**このファイルは「状況 → 次にやること」の表です。** 上から全部読む必要はありません。
今の状況に合う節を 1 つ開いて、**番号どおりに 1 つずつ**やってください。

> 実行エージェントは Skill ツールを持たないので、このファイルは次のコマンドでパスを出して Read します:
> `bash scripts/plugin-root.sh --skill mule-guide`
> このファイルの中のコマンドは、**すべてプロジェクト直下で実行する**前提で書いてあります。

---

## 最初に覚えておく 3 つ

1. **調べる前に引く。** エラーが出たら、Web 検索や試行錯誤の**前に**
   `bash scripts/gotcha-lookup.sh '<エラーの原文の一部>'` を実行する。答えが書いてあることが多い。
2. **このリポジトリの外を読まない。** 隣のフォルダに別の Mule プロジェクトがあっても開かない。
   そこの `pom.xml` の組織 ID や接続先を写すと、**別の組織に publish する事故**になる。
3. **分からない値は推測で埋めない。** 組織 ID・接続情報・パスワード・版は、人に聞くか、下に書いた
   コマンドで取る。**分からなければ止まって聞く。** 推測で書いて試すのが一番時間を失う。
   ただし **Anypoint にある値 (URL・ID・状態) は API で取れる。** 人に画面を見てもらう前に
   5 の「Anypoint にある値の取り方」をやる。

> **ちょっと試したいだけのときは、この手順を全部やらなくてよい。**
> `python3 scripts/casual.py on` でカジュアルモード (期限つき) にすると、台帳・TDD・締め方・層の検査の
> 強制が外れ、**git が無視する場所になら秘密も書ける**。本番へのデプロイと publish 前の jar 検査は
> 外れない。詳しくは `bash scripts/plugin-root.sh --skill mule-casual`。戻すのは `casual.py off`。

---

## 1. エラーが出た

1. エラーの原文から、**固有名詞や数字を除いた特徴的な部分**をコピーする。
   例: `Cannot coerce Object to String`、`ORA-12505`、`Stream Compatible`、`Could not find error`
2. 引く:
   ```bash
   bash scripts/gotcha-lookup.sh 'Cannot coerce Object to String'
   ```
3. **当たったら (exit 0)**: 出てきた項目の「直し方」をそのままやる。
   ただしその項目の「根拠」の行を見て、**同じ DB 製品・同じコネクタか**だけ確かめる
   (例: 「Derby で実測」と書いてあって自分が Oracle なら、そのまま当てはまらないことがある)。
4. **当たらなかったら (exit 1)**: もっと短い言葉で引き直す。エラー型だけにするのが効く。
   ```bash
   bash scripts/gotcha-lookup.sh 'MULE:EXPRESSION'
   bash scripts/gotcha-lookup.sh 'ORA-00942'
   ```
5. それでも無ければ、次の順に調べる。**上から順に。当たったらそこで止まる。**
   1. コネクタの要素名・操作名・パラメータ名の話 → `reference/mule-schema/INDEX.md` を開く
   2. Anypoint 側 (API Manager、Exchange、Runtime Manager、ゲートウェイ) の話 → 5 の「Anypoint にある値の取り方」。
      手順そのものが要るなら `bash scripts/plugin-root.sh --skill platform-assistant` を Read
   3. 公式マニュアル
6. 分かったら**必ず書き残す**。次の人が手順 2 で引けるように。
   ```bash
   bash scripts/k-new.sh T-003     # ← 自分のゴール id。出てきたパスに書く
   ```
   書く形: `症状 (原文)` / `原因` / `直し方` / `根拠のコマンドと結果` / `どこで調べたか`

**やってはいけない**: エラー文を読まずに実装を変えて再実行を繰り返す。1 回目の失敗の原文を
読まずに 2 回目を流すと、同じエラーをもう 1 回見るだけです。

---

## 2. 書き始める前 (ゴールを 1 件もらったとき)

順番に読む。**全部読まない。**

1. もらったゴールのファイル (`tasks/T-NNN.md`)。`done_when` が**終わりの条件**。
2. 受け入れ条件: `samples/<resource>/*.in.json` と `*.out.json`。**これが正解。変えない。**
3. `api/*.raml` の、自分が作るリソースの部分だけ。
4. 基礎知識の索引 → 触る主題だけ開く:
   ```bash
   bash scripts/plugin-root.sh knowledge/mule-basics.md       # 索引。表から主題を選ぶ
   bash scripts/plugin-root.sh knowledge/basics/db.md          # 例: DB を触るならこれだけ
   ```
5. 写経元 (同じ形で書くためのお手本):
   ```bash
   bash scripts/plugin-root.sh template/reference/README.md    # どのお手本が何の形かの表
   ```
6. TDD の順番: `bash scripts/plugin-root.sh --skill mule-tdd` を Read。
   **先にテストを書いて落ちることを確かめる (Red)。それから実装する (Green)。**

---

## 3. pom.xml に依存を足すとき

1. **XML に書いた名前空間ごとに、対応するものが pom にあるか確かめる。**
   | XML に書いたもの | pom に要るもの |
   |---|---|
   | `apikit:config` / `apikit:router` | `org.mule.modules:mule-apikit-module` (classifier `mule-plugin`) |
   | `db:...` | `org.mule.connectors:mule-db-connector` (classifier `mule-plugin`) |
   | `http:...` | `org.mule.connectors:mule-http-connector` (classifier `mule-plugin`) |
   | JDBC ドライバ (Oracle など) | `<dependency>` **と** mule-maven-plugin の `<sharedLibraries>` の**2 箇所** |
2. **版は推測しない。** 次のどちらかで取る:
   ```bash
   grep -n 'mule-apikit-module\|mule-db-connector\|mule-http-connector' reference/mule-schema/INDEX.md
   ```
   INDEX.md が無ければ `bash scripts/schema-index.sh` で作る。
3. **他のプロジェクトの pom から写さない。** (最初に覚えておく 3 つ の 2)
4. JDBC ドライバの 2 箇所の書き方は写経元にある:
   ```bash
   bash scripts/plugin-root.sh template/reference/pom-fragments.xml
   ```
5. 足したら確かめる:
   ```bash
   mvn -q clean package -DskipTests
   ```
   `Can't resolve http://www.mulesoft.org/schema/mule/<名前>/current/...xsd` と出たら、その `<名前>` の
   モジュールが pom に無い。表の 1 に戻る。

---

## 4. MUnit を書くとき

`bash scripts/plugin-root.sh --skill mule-munit` を Read して、その「書く前に 30 秒で確かめる 5 つ」を
やる。特に次の 4 つは毎回踏まれている:

1. **外部に行く操作 (`db:*`、`http:request`) は全部 `mock-when` する。** 1 つでも漏れると実 DB に
   接続しに行って、120 秒待ってタイムアウトする。**実装が呼ぶ `db:select` を全部数える** (存在確認の
   select のような、目立たないものも)。
2. **assert の式に `default` を付けない。** 付けると値が無くても通る = 何も検証していない。
3. **`munit:payload` に `output application/json` を付けない。** プレーンなオブジェクトで渡す。
   ```xml
   <munit:payload value='#[{ quantity: 5.0 }]'/>                          <!-- ○ -->
   <munit:payload value='#[output application/json --- { quantity: 5.0 }]'/>  <!-- × 後段で Stream Compatible -->
   ```
4. **APIkit の振り分け flow を叩くなら、attributes を型付けする。** お手本をそのまま写す:
   ```bash
   bash scripts/plugin-root.sh template/reference/router-test.xml
   ```

書いたら、**テストに牙があるか**を機械で測る (手で細工して目で見ない):
```bash
bash scripts/teeth-check.sh --file src/test/munit/<resource>-test.xml \
     --old '<壊す前の文字列>' --new '<壊した後の文字列>' --case <case 名>
```
exit 0 なら牙あり。exit 2 なら出てきた理由をそのまま読む。

---

## 5. 分からない値があるとき (組織 ID、接続情報、パスワード、版)

**推測で書かない。止まって、次の表のとおりに取る。**

| 値 | 取り方 | 置き場所 |
|---|---|---|
| 組織 ID (`--group-id`、pom の `groupId`) | 人に聞く。または `anypoint-cli-v4 account business-group list` | pom の `groupId` |
| DB の接続先 (host / port / サービス名) | 人に聞く | `src/main/resources/config/*.yaml` |
| DB のパスワード、Client Secret | **人に聞く。ファイルに書かない** | 環境変数 / Runtime Manager の secure property |
| コネクタの版 | `reference/mule-schema/INDEX.md` | pom |
| Mule ランタイムの版 | `context/sources.yaml` の `mule_version` | pom の `app.runtime` |
| CloudHub 2.0 に置いたアプリの公開 URL | `python3 scripts/ch2-public-url.py <app> <environment>` | sandbox.yaml の `public_url`、deploy ゴールの `done_when` |
| Flex Gateway に置いた API の公開 URL | `python3 scripts/gateway-public-url.py <インスタンス ID か instanceLabel>` | policy ゴールの `done_when` |
| そのほか Anypoint にある値 (ID、状態、設定) | 下の「Anypoint にある値の取り方」 | 使う場所 |

- **聞くときは、分からないものを全部まとめて 1 回で聞く。** 1 つずつ聞き直さない
  (1 つのゴールで 5 往復した実例があります)。
- 設定ファイルの既定値に `SET_...` を置くとき、**`port` のような数値の項目だけは `"0"` にする**。
  `SET_...` のままだと MUnit が起動時に `NumberFormatException` で落ちる。
- 秘密の値 (パスワード、Secret) を **ファイル・コメント・進捗メモに書かない**。書くのは「どこから読むか」。

### Anypoint にある値の取り方 (人に画面を見てもらう前に)

**Anypoint の画面に出ている値は、ほぼすべて API でも取れる。** 「API から取れない」と決める前に、
上から順にやる。

1. 値の**項目名**で、公式の API 仕様 (36 本) を引く。項目名は英語の camelCase。画面の表示名から推測してよい:
   ```bash
   python3 scripts/portal-search.py publicUrl
   ```
   どの API のどの操作がその項目を返すかと、そのまま流せる `anypoint-api.py` の行が出る。
2. 出た行をそのまま流す。パスに `{gatewayId}` のような変数が残っていたら、「の値」の行に書いてある
   一覧の操作で先に ID を取る:
   ```bash
   python3 scripts/anypoint-api.py '/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways'
   python3 scripts/anypoint-api.py '/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways/<id>' --find publicUrl
   ```
   `{org}` と `{env}` は自動で埋まる (pom の groupId と sandbox.yaml の environment)。資格情報は環境変数
   `ANYPOINT_CLIENT_ID` / `ANYPOINT_CLIENT_SECRET` から読む。**Secret をコマンド行に書かない。**
   無ければ exit 2。人に「export してから claude を起動し直す」を頼む (Bash は毎回新しいシェル)。
3. 外れたら (exit 1) 別の言い方で 1 に戻る (`url` / `host` / `endpoint` / `domain`)。
   **仕様に書かれていない項目もある** (Private Space の `dnsTarget` は応答にあるが仕様に無い)。
   値を持っていそうなもの (ゲートウェイ、Private Space、アプリ) の名前で 1 を引き、その一覧か詳細を
   `--find <項目名>` 付きで GET する。
4. 3 語引いて、GET の応答にも無ければ、そこで初めて人に聞く。**引いた語と叩いたパスを全部**添える。
5. 取れたら `bash scripts/k-new.sh <ゴール id>` が出したパスに「どの API のどの項目か」を書く。

`anypoint-api.py` は **読むだけ** (GET)。作る・変える操作はゴールの手順と `authorizations.yaml` の許可に従う。

---

## 6. デプロイするとき

`bash scripts/plugin-root.sh --skill mule-deploy` を Read。**順番を変えない。**

```bash
bash scripts/deploy-precheck.sh      # 1) 聞くことを全部洗い出す。exit 1 なら、出たものを 1 回でまとめて人に聞く
bash scripts/deploy-config.sh        # 2) pom にデプロイ設定を入れる
bash scripts/bump-version.sh         # 3) 版を上げる (同じ版は Exchange に上書きできない)
mvn clean package                    # 4) 作る
bash scripts/jar-leak-check.sh       # 5) jar に秘密が入っていないか。exit 0 でなければ次に進まない
mvn deploy                           # 6) Exchange に publish
mvn deploy -DmuleDeploy              # 7) 配置 (clean を付けない)
python3 scripts/smoke-check.py --dry-run <URL>   # 8) 何を送るか先に見る
python3 scripts/smoke-check.py <URL>             # 9) 実際に当てる
```

- **`mvn clean deploy -DmuleDeploy` を 1 行で打たない。** Exchange の 404 で必ず落ちる。
- 5 を 6 より後にしない。publish したあとに気付いても取り返せない。
- **公開エンドポイントを付けるかは、1 で人に聞く** (`sandbox.yaml` の `ingress`)。
  `public` なら `python3 scripts/ch2-public-url.py <app> <environment>` で公開 URL を取る。
  `gateway` なら**付けない** (既に付いていたら `--remove` で外す)。置けたかは
  `python3 scripts/app-status.py <app>` (RUNNING で exit 0)、外からの URL は 7 の 3 で取る。
  この組織にゲートウェイがあるかを含め、候補は `python3 scripts/env-probe.py` が出す。
- **`smoke-check.py` はアプリの URL に当てる。** RAML の `baseUri` のパス (`/api`) を足すので、
  ゲートウェイの URL に当てると `/api/api` になって全件 404 になる。
- `authorizations.yaml` の `deploy.sandbox` が `allowed` でないと hook が止める。
  **止められたら理由を人に伝えて止まる。書き換えない。回避しない。**

---

## 7. ポリシーを当てるとき (stage: policy)

0. **ポリシーを探す・設定キーを見る・付ける・外すは、手順が 1 本にまとまっている**:
   ```bash
   bash scripts/plugin-root.sh --skill mule-policy    # を Read。典型的なポリシーの表と順番
   python3 scripts/policy.py find <語>                   # 探す (assetId と version)
   python3 scripts/policy.py config <assetId>            # 設定キー (**推測しない**。誤キーでも 201 が返る)
   python3 scripts/policy.py apply <インスタンス> <assetId> --config '<JSON>'
   python3 scripts/policy.py remove <インスタンス> <policyId>
   ```
1. **自分で API Manager を叩いて調べ始める前に**、既知のことを読む:
   ```bash
   bash scripts/plugin-root.sh knowledge/gotchas/api-manager.md
   ```
   インスタンスの作り方、flexGateway の制約、RAML の Exchange への置き方がここに書いてある。
   **読まずに試すと、書いてあることを何度も踏み直す** (実例があります)。
2. 効いたかどうかは表示ではなく実測で決める:
   ```bash
   bash scripts/policy-check.sh <URL> client-id /inventory   # 認証なしで 401、ありで 2xx なら exit 0
   ```
   3 つ目は **GET して 2xx が返るリソース**。省くと `/` を叩き、アプリによっては 404 になって落ちる。
   認証ありでも 401 なら、その `CLIENT_ID` がインスタンスと契約していない (出力に確かめ方が出る)。
3. **Flex Gateway に置いた API の URL は、API インスタンスには載っていない。ゲートウェイの側にある。**
   次の 1 行で取る。人に画面を見てもらわない。推測したホスト名で試さない:
   ```bash
   python3 scripts/gateway-public-url.py <インスタンス ID か instanceLabel>   # → https://<ゲートウェイ>.<dnsTarget>/<パス>
   ```
   出た URL を 2 の `<URL>` と、policy ゴールの `done_when` に書く。
   **標準エラーに「upstream に外から直接届く」と出たら、ゲートウェイを迂回できる = まだ守れていない。**
   台帳の `evidence` と報告にそう書く (直し方は `knowledge/gotchas/api-manager.md` の最初の項目)。

---

## 8. 止まるとき・人に聞くとき

1. 止まる前に必ず:
   ```bash
   bash scripts/goal-state.sh
   ```
   | exit | 意味 | やること |
   |---|---|---|
   | 0 | 全ゴール passed | 完了を報告する |
   | 1 | **まだ進められるゴールがある** | **止まらない。** `/mule-run` の手順で次のゴールに進む |
   | 2 | 進められるものが無い (人の判断待ち) | 出力の「止まっている」の行をそのまま人に伝えて止まる |
2. 報告は必ず 3 ブロックで締める:
   ```
   ## 現在地
   <何がどこまで終わったか 1 行>

   ## 次にすること
   <1 つだけ。コマンドはそのまま貼れる形で>

   ## そのあと
   <それが終わると何が起きるか 1 行>
   ```
3. **人に聞いてよいもの**: 分からない値 (5 の表)、受け入れ条件の承認、PR のマージ、本番、許可
   (`authorizations.yaml`)。**聞かずに自分で決めてよいもの**: それ以外の実装の細部
   (`context/decisions.yaml` の `defaults` に従い、`docs/spec/<name>.md` の「仮定」に書く)。

---

## やってはいけないこと (と、代わりにやること)

| やってはいけない | 代わりに |
|---|---|
| エラーを見て、すぐ Web 検索する | `bash scripts/gotcha-lookup.sh '<原文>'` を先に |
| 隣のプロジェクトの pom / 設定を読む・写す | このリポジトリとプラグインだけを読む。値は人に聞く |
| 分からない値を推測で埋めて試す | 5 の表で取る。無ければ止まって聞く |
| 「API から取れない」と決めて、人に Anypoint の画面を見てもらう | `portal-search.py '<項目名>'` → `anypoint-api.py`。3 語引いて外れてから聞く (5 の「Anypoint にある値の取り方」) |
| Connected App の Secret をコマンド行に書く (`export ANYPOINT_CLIENT_SECRET=<値> && curl ...`) | `anypoint-api.py` を使う。環境変数から読むので会話の記録に残らない |
| `samples/` やテストの期待値を実装に合わせて変える | 実装を直す。期待値が間違っていると確信したら**止まって報告** |
| `mock-when` を省いて実 DB に繋ぐ | 全部 mock する (4 の 1) |
| assert に `default` を付ける | 付けない (4 の 2) |
| 聞きたいことを 1 つずつ聞く | まとめて 1 回で聞く |
| プラグインのスクリプト (`scripts/*.sh`) を書き換える | 書き換えずに症状を K ファイルに書き、`/mule-learn` でプラグインに PR する |
| hook に止められて、別の書き方で回避する | 止められた理由を人に伝えて止まる |
| `authorizations.yaml` を書き換える | それは人が書くもの。待つ |
| 秘密の値をファイルやメモに書く | 「どこから読むか」だけ書く |

---

## 自分で確かめるコマンド (困ったら上から)

```bash
bash scripts/gotcha-lookup.sh '<エラーの原文の一部>'   # 既知か
python3 scripts/portal-search.py '<項目名>'                 # Anypoint の値を、どの API が返すか
python3 scripts/anypoint-api.py '<パス>' --find <項目名>    # 実際に GET して探す (読むだけ)
bash scripts/preflight.sh                                # 土台は健全か (git、RAML、ビルド)
mvn -q clean test -Dmunit.test=<file>-test.xml           # そのテストだけ
bash scripts/coverage-check.sh                           # 全 flow が MUnit から呼ばれているか
bash scripts/teeth-check.sh --file ... --old ... --new ... --case ...   # テストに牙があるか
bash scripts/spec-check.sh                               # RAML・サンプル・実装のずれ
bash scripts/goal-state.sh                               # 止まってよいか
```
