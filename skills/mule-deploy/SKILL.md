---
name: mule-deploy
description: デプロイのループ。マージ済みのアプリを Sandbox (CloudHub 2.0 か Runtime Fabric) に置き、samples/ の期待値で疎通を確かめ、結果を knowledge/ に残す。失敗は学習ループの元データ (failures.jsonl) に戻す。本番は扱わない。
argument-hint: "[--verify-only <base-url>  デプロイ済みの URL に疎通確認だけ行う]"
---

実行ループの出口 (PR マージ) と学習ループの入口をつなぐのがこのループの役目です。
「デプロイして終わり」ではなく、**samples/ の期待値が配置先でも成り立つか** を確かめ、成り立たなければその指紋を `knowledge/failures.jsonl` に残すところまでが 1 周です。

## ゲート (両方満たすときだけ動く。判定するのは人ではなく hook)

1. `context/deployment/authorizations.yaml` の `deploy.sandbox` が `allowed`。`denied` なら人が口頭で許可しても動かない (ファイルを直すのは人)。
2. 台帳に `stage: deploy` のゴールがある。無ければ先に 1 件切ってから進む (台帳の外で作業しない)。

この 2 つが揃っていれば **デプロイのたびに人へ確認を取らない**。許可はもともと 1 のファイルに
書いてあり、会話で聞き直すのは同じことを二度確かめているだけだから。判定者を人から機械へ移す
のはこのリポジトリの他のループと同じ作りで、`done_when` が実装の判定者であるように、
`authorizations.yaml` がデプロイの判定者になる。

判定は `scripts/deploy-guard.py` (PreToolUse hook)。`mvn ... deploy` / `-DmuleDeploy` /
`anypoint-cli ... deploy` を捕まえて、次を見て allow か deny を返す。

| 見るもの | deny になる条件 |
|---|---|
| `authorizations.yaml` の `deploy.sandbox` | `allowed` でない |
| `sandbox.yaml` の `environment` と `pom.xml` の `<environment>` | どちらかが Production 系の名前 |
| 同上 | 両方とも空 (Sandbox だと確かめられない) |

deny のときコマンドは実行されず、理由が返る。**deny を回避する経路 (別コマンド、MCP、pom の
直接編集) を探さない。** 止まったら理由をそのまま人に伝えて終わる。ファイルを直すのは人。

`production` は常に人の手作業。実際に `mvn` が使う環境名は pom に入るので、hook は
sandbox.yaml だけでなく pom の `<environment>` も見る。
MCP の `deploy_mule_application` は使わない。経路は下の `mvn clean deploy -DmuleDeploy` だけにして、pom に何が書かれたかを人が diff で追えるようにする。

## 公開エンドポイントを付けるか (`ingress`) — **デプロイの前に必ず決める**

| `ingress` | 何が起きるか | 使うとき |
|---|---|---|
| `public` | アプリに公開 URL を付ける (`ch2-public-url.py`)。その URL を直接叩ける | 手早く動かしたい。ポリシーで守る必要がない |
| `gateway` | アプリに公開 URL を**付けない**。Flex Gateway 経由だけにする | ポリシー (認証・流量) を効かせる。**迂回路が無いのはこちらだけ** |

**両方を有効にしない。** 公開 URL を付けたままゲートウェイを前に置くと、ゲートウェイ経由は 401 でも
アプリの URL を直接叩けてしまいます (inventory3-api で実測: `GET /inventory` が認証なしで 200)。
**「ポリシーが付いている」という表示と実際の保護が食い違うのは、ポリシーが無いより危険です。**

どちらにするかは**人が決めます**。決まったら**エージェントが `sandbox.yaml` に書きます** (聞かずに埋めないのが線で、人にファイルを開かせるのが線ではない)。この組織にそもそも Flex Gateway が
あるかどうかも含めて、候補は機械が出します:

```bash
python3 scripts/env-probe.py        # 環境 / デプロイ先 / Flex Gateway の一覧と、sandbox.yaml に書く形
```

`ingress: gateway` のときの流れ:

0. **既に `public` で動いているものを `gateway` に切り替えるときは、順番を間違えない。**
   ゲートウェイの upstream がアプリの**公開** URL を指しているなら、**先に内部 URL へ向け替えてから**
   公開 URL を外す (逆にすると経路ごと切れる)。**URI は末尾にスラッシュを付ける** —
   `/api` だと `/api` + `inventory` が `/apiinventory` になって 404 になる
   (`knowledge/gotchas/api-manager.md`)。
   ```bash
   python3 scripts/anypoint-api.py '/apimanager/api/v1/organizations/{org}/environments/{env}/apis/<id>/upstreams'
   # → PATCH .../upstreams/<upstreamId>  {"uri":"https://<app>.internal-<dnsTarget>/api/"}
   ```
   向け替えたら、**ポリシーを一時的に外して素通しで 200 を確認し、すぐ同じ設定で付け直す。**
   ポリシーが付いたままだと 401 で止まり、upstream が正しいかは分からない (2026-09-12 実測)。
1. アプリを置く (公開 URL は付けない)。既に付いているなら外す — `python3 scripts/ch2-public-url.py --remove <app> <env>`
2. deploy ゴールの `done_when` は `python3 scripts/app-status.py <app>` (RUNNING なら 0)。
   **外から疎通できないのが正しい状態**なので、ここで公開 URL に当てない。
3. `stage: policy` のゴールでゲートウェイに API インスタンスを作り (upstream はアプリの**内部** URL)、
   ポリシーを当てる → `python3 scripts/gateway-public-url.py <インスタンス>` が外からの URL を出す。
4. 疎通は `python3 scripts/smoke-check.py --no-basepath <ゲートウェイの URL>`。
   **`--no-basepath` を付ける** (ゲートウェイの upstream が既にアプリ側の `/api` を含むので、
   足すと `/api/api` になって全件 404 になる)。

## 台帳との関係

通常は `/mule-run` が `stage: deploy` のゴールを取り出したときに、進捗エージェントがこの手順を実行する。そのゴールの `done_when` (smoke-check) が判定者で、このスキル単体の「置けた」は成功ではない。人が直接 `/mule-deploy` と言ったときも、台帳に deploy ゴールが無ければ先に 1 件切ってから進む (台帳の外で作業しない)。

## 読むもの

1. `context/deployment/sandbox.yaml` — kind (cloudhub2 / rtf)、environment、target、**ingress**、public_url。**行そのものが無いこともある** (v0.6.45 より前に `/mule-init` したリポジトリ)。その場合は人に 1 回聞いて、答えをエージェントが足す。
   **`ingress` が `unknown` のままなら、そこで止まって人に聞く** (下の「公開エンドポイントを付けるか」)。
2. `context/deployment/authorizations.yaml`
3. `samples/` — 疎通確認の期待値。これを変えない。
4. 環境変数 `ANYPOINT_CLIENT_ID` / `ANYPOINT_CLIENT_SECRET` (Connected App、client_credentials)。無ければ人に export してもらう。値を会話や pom に書かない。
5. `config/*.yaml` の `SET_` プレースホルダ (`scripts/deploy-precheck.sh` が列挙する)。実値のうち
   password / secret / credential を含むものは人が Runtime Manager の secure property で入れる
   (エージェントが API 経由で設定しない)。それ以外は `sandbox.yaml` の `properties` に書いてよい。

## 手順

1. **前提を確かめる。** まず `bash scripts/deploy-precheck.sh` を 1 回走らせる。**exit 1 なら、
   出力に列挙された項目 (Connected App の資格情報、デプロイ先 (shared か Private Space か)、
   `config/*.yaml` に残っている `SET_` プレースホルダ) を 1 回のやり取りでまとめて人に確認する。**
   1 件ずつ聞き直さない (実測: inventory3-api T-006 で Connected App の資格情報・DB のパスワード・
   Private Space の指定が別々のタイミングで発覚し、そのたびに止まってやり取りが 5 往復以上に
   膨らんだ。まとめて 1 回聞けば防げた)。
   確認が終わったら、ゲート 2 つ、`git status` が clean で `main` (または PR をマージしたブランチ) に
   いること、`mvn -q clean test` が通ることを確かめる。通らないものは置かない。
2. **pom にデプロイ設定を入れる。** `bash scripts/deploy-config.sh`。sandbox.yaml から `cloudhub2Deployment` か `runtimeFabricDeployment` と Exchange の `distributionManagement` を入れる。認証は `${env.*}` 参照なので秘密は pom に残らない。
   - `groupId` が組織 ID (UUID) でないと止まる。CH2 / RTF は Exchange 経由でしか置けず、Exchange のアセットは組織 ID を groupId にする決まり。`dx mule project create --group-id <組織 ID>` で作っていれば通る。
   - `~/.m2/settings.xml` に `<server><id>anypoint-exchange-v3</id>` (Connected App の `~~~Client~~~` / `<id>~~~Secret~~~` 形式) が無いと `mvn deploy` が 401 になる。docs/mulesoft-tools.md を案内する。
3. **置く。** 先に `bash scripts/bump-version.sh` で pom の版を上げる (Exchange は同一版を上書きできないので 2 回目から落ちる)。開始時刻を控えて、**4 つに分けて**打つ:
   ```bash
   mvn clean package                # 1) 作る
   bash scripts/jar-leak-check.sh   # 2) 混入を見る。**exit 0 でなければ publish しない**
   mvn deploy                       # 3) Exchange に publish する
   mvn deploy -DmuleDeploy          # 4) publish 済みのアセットを配置する
   ```
   **2 を 3 より前に置くこと。** `-DattachMuleSources` はプロジェクト全体を丸ごと jar に入れ
   `.gitignore` を見ないので、**publish したあとに気付いても取り返せません** (Exchange に上がった
   時点で組織の全員から見えます)。v0.6.27 はこの検査を publish の**あと**に書いていました。
   **検査があっても、位置が後ろなら何も防ぎません。** 詳細は `knowledge/gotchas/build.md`。
   **1 コマンドにまとめない。** `mvn clean deploy -DmuleDeploy` は
   `Failed to retrieve artifact information from Exchange. Reason: 404 There is no asset matching
   given parameters.` で**必ず**落ちます。`muleDeploy` が、まだ publish されていないアセットを
   先に参照するためです (inventory2-api で実測)。1 段目が済んでいれば 2 段目は `clean` を付けません
   (付けると成果物が消えてもう一度 publish が要ります)。
   同じ 404 は `<businessGroupId>` が無いときにも出ます (認証トークンの既定組織 = Root を見る)。
   `deploy-config.sh` が pom に入れるので、手で消さないこと。
   出力の末尾に配置先の URL か status が出る。RTF は Ingress の URL が sandbox.yaml の `public_url` になる。
   **`ingress` で分かれる:**
   - `public` … CH2 で `public_url` が空なら `python3 scripts/ch2-public-url.py <app> <environment>` で既定の公開 URL を付けて取る。`runtime-mgr application modify --publicEndpoints` は成功を返すが効かず、`modify` は properties を消す (`knowledge/gotchas/deploy.md`)。取れた URL を sandbox.yaml の `public_url` と deploy ゴールの `done_when` に書く。
   - `gateway` … **公開 URL を付けない。** 既に付いていたら `python3 scripts/ch2-public-url.py --remove <app> <environment>` で外す
     (残っているとゲートウェイを迂回できる)。`python3 scripts/app-status.py <app>` が 0 になれば置けている。
   終わったら `bash scripts/run-log.sh deploy <kind> <environment> ok|failed <秒>` を記録する。

4. **待つ。** `anypoint-cli-v4 runtime-mgr application describe <app> --environment <env> -o json` の `status` が `RUNNING`/`APPLIED` になるまで 30 秒間隔で最大 10 分。`FAILED` ならログを `runtime-mgr application logs` で取り、手順 6 へ。
5. **疎通を確かめる。** `ingress: public` なら `python3 scripts/smoke-check.py <public_url>`、
   `ingress: gateway` なら**ポリシー段でインスタンスを作ってから**
   `python3 scripts/smoke-check.py --no-basepath <gateway-public-url.py が出した URL>`。samples の全ケースを配置先に投げて out.json と比較する。要求が `POST /<resource>` でないケースには `<case>.req.json` (method / path / headers) を隣に置く。samples の期待値は変えない。結果は `knowledge/deploy-log.jsonl` に 1 ケース 1 行。
   - ここで **MUnit は通るのに配置先では違う** ものが本命の収穫。mock で隠れていた接続先、properties の差、`api.autodiscovery`、TLS など。
6. **失敗を学習ループに戻す。** 落ちた原因が分かった (直った) 瞬間に `knowledge/failures.jsonl` に 1 行。category は `/mule-learn` の固定語彙から `deploy-config` / `deploy-runtime` / `deploy-connectivity` を使う。この 3 つに当てはまらなければ語彙の他の値を見て、それでも無ければ `other`。**自分で言葉を作らない** (自作の値は数えられず昇格もされない)。`scope` はこのリポジトリの環境固有なら `repo`、CH2 / RTF なら誰でも踏むものなら `generic`。
7. **締める。** 必ず「現在地 / 次にすること / そのあと」の 3 ブロック。次にすることは 1 つ。
   - 全ケース match → 「次に作る API はありますか」か、`failures.jsonl` に 2 回以上の指紋があれば `/mule-learn`。
   - mismatch がある → 原因の仮説を 1 行で示し、`/mule-start` で仕様に戻るか、人が環境 (properties / 接続先) を直すかを番号で聞く。
   - 本番へは進めない。「本番は Runtime Manager から人が行う」とだけ書く。

## `--verify-only <base-url>`

すでに人が置いたアプリに対して手順 5 と 6 だけ行う。デプロイの許可は要らない (読むだけ)。

## CloudHub 2.0 と Runtime Fabric の違い (ここで詰まりやすい)

| | CloudHub 2.0 | Runtime Fabric |
|---|---|---|
| `target` | 共有スペース名 (`Cloudhub-US-East-2` など) か Private Space 名 | fabric 名 (`runtime-mgr rtf list` で出る) |
| サイズ | `vCores` (0.1 / 0.2 / 0.5 / 1 …) | `cpu_reserved` / `memory_reserved` |
| 公開 URL | 共有スペースなら `<app>-<hash>.<region>.cloudhub.io`、Private Space は人が Ingress を用意 | fabric の Ingress。`public_url` に人が書く |
| Java | `--javaVersion` / `javaVersion` (8 / 17) | 同じ |

どちらも Exchange への publish が前段にあるので、`groupId` = 組織 ID と Exchange の認証が共通の前提。
ここに書いてあるのは公式手順で、実測で得た地雷は `knowledge/gotchas/deploy.md` (配備) と `knowledge/gotchas/api-manager.md` (ポリシー) に件数つきで増やし、`knowledge/gotchas.md` の索引の件数も直す (根拠の無い項目は書かない)。

## 禁止

- Production 名の環境に向けること。
- `authorizations.yaml` を書き換えること。
- smoke-check を通すために samples の期待値を変えること。
- 秘密 (client secret、パスワード) を pom / 会話 / ログに書くこと。
- 結果だけ書いて終わること。**必ず次の一手を書く。**
- `deploy-guard.py` の deny を回避すること (別経路を探す、pom を直接書き換える、hook を外す)。
