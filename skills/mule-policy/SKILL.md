---
name: mule-policy
description: API Manager のポリシーを、探す / 設定キーを見る / 付ける / 外す / 効いたか実測する。典型的なポリシー (client-id-enforcement、rate-limiting、jwt-validation、ip-allowlist、cors、header-injection ほか) の表と、設定を推測しないための手順。stage: policy のゴールを進めるとき、ポリシーの名前や設定キーが分からないとき、付けたのに守れていないときに使う。
---

# ポリシーを探す・付ける・外す

> 実行エージェントは Skill ツールを持たないので、このファイルは次でパスを出して Read します:
> `bash scripts/plugin-root.sh --skill mule-policy`
> コマンドは**すべてプロジェクト直下**で実行します。

**前提**: `context/deployment/authorizations.yaml` の `policy.sandbox` が `allowed`。
`denied` なら付けない・外さない。**ファイルを書き換えない。理由をそのまま人に伝えて止まる。**
資格情報は環境変数 `ANYPOINT_CLIENT_ID` / `ANYPOINT_CLIENT_SECRET` (無ければ人に頼む。値をコマンド行に書かない)。

---

## 0. 順番 (これだけ守る)

```bash
bash scripts/policy.sh find rate                  # 1) 探す           → assetId と version
bash scripts/policy.sh config rate-limiting       # 2) 設定キーを見る  → 推測しない
bash scripts/policy.sh list <インスタンス>         # 3) 今ついているもの → policyId と order
bash scripts/policy.sh apply <インスタンス> rate-limiting --config '<JSON>'   # 4) 付ける
bash scripts/policy-check.sh <URL> client-id /inventory                      # 5) 効いたか実測 ★
bash scripts/policy.sh remove <インスタンス> <policyId>                       # 外す
```

`<インスタンス>` は API インスタンス ID / `instanceLabel` / `assetId` のどれでもよい。
`<URL>` は Flex Gateway なら `bash scripts/gateway-public-url.sh <インスタンス>` が出したもの。

**5 を飛ばさない。** 適用は 201 が返るだけで、**守れているかは何も言っていません**
(設定キーを間違えていても 201 が返ります。2026-09-12 実測)。

---

## 1. 典型的なポリシー (まずこの中から選ぶ)

| したいこと | assetId | 主な設定キー | 注意 |
|---|---|---|---|
| 利用者を限定する (Client ID) | `client-id-enforcement` | `credentialsOriginHasHttpBasicAuthenticationHeader` (`customExpression` か `httpBasicAuthenticationHeader`)、`clientIdExpression`、`clientSecretExpression` | **利用者アプリと契約が要る** (5 節)。契約が無いと認証ありでも 401 |
| JWT を検証する | `jwt-validation` | `jwtOrigin`、`signingMethod`、`jwtKeyOrigin`、`skipClientIdValidation` | 必須項目が 9 個ある。`config` で全部見る |
| 外部 IdP の OAuth2 | `external-oauth2-access-token-enforcement` / `openidconnect-access-token-enforcement` | トークン検査先の URL とスコープ | Client Provider の設定が先 |
| Basic 認証 | `http-basic-authentication` | ユーザ名 / パスワード | 試験用途だけにする |
| 流量を抑える | `rate-limiting` | `rateLimits` (上限と時間窓の組)、`keySelector`、`exposeHeaders` | 利用者ごとに分けるなら `keySelector` |
| 契約の SLA 層ごとに抑える | `rate-limiting-sla-based` / `throttling-sla-based` | SLA 層 | 契約が要る |
| 瞬間的な山を均す | `spike-control` | 同時実行数、待ち行列 | 遅延を足すので API の性質を見る |
| 送信元 IP を絞る | `ip-allowlist` / `ip-blocklist` | IP の一覧 | ゲートウェイから見た送信元 (LB の内側だと全部同じことがある) |
| 危険なペイロードを弾く | `json-threat-protection` / `xml-threat-protection` | 深さ、要素数、長さの上限 | |
| ブラウザから呼ばせる | `cors` | 許可オリジン、メソッド | |
| ヘッダを足す / 消す | `header-injection` / `header-removal` | `inboundHeaders` / `outboundHeaders` (`{"key","value"}` の配列) | upstream に文脈を渡すときに使う |
| ログを出す | `message-logging` | 出力する式、レベル | 秘密を書き出さないこと |
| LLM / MCP / A2A 向け | `llm-token-rate-limit`、`mcp-*`、`a-two-a-*` | ポリシーごとに違う | Agent Fabric 系。`find` で探す |

この組織から見えるポリシー資産は **131 件** (2026-09-12 実測)。表に無いものは `find` で探す:

```bash
bash scripts/policy.sh find jwt        # 語は短く、英語で
bash scripts/policy.sh find mcp
```

---

## 2. 設定キーは必ず `config` で見る

```bash
bash scripts/policy.sh config client-id-enforcement
#   credentialsOriginHasHttpBasicAuthenticationHeader  string  必須 ...
#   (条件つき) clientIdExpression                      string  任意 ...
#   選べる値: customExpression / httpBasicAuthenticationHeader
```

- `(条件つき)` は「別のキーがある値のときだけ意味を持つ」もの (スキーマの `if/then`)。
- **間違ったキーを渡しても 201 が返ります。** 効くかどうかは 5 の実測でしか分かりません。
- 版を省くと Exchange の最新が使われます。**同じ組織の他のインスタンスと版を揃えたい**ときは
  `bash scripts/policy.sh list <他のインスタンス>` で使っている版を見て、明示的に渡す。

実例 (この形で 201 になった。2026-09-12 実測):

```bash
bash scripts/policy.sh apply inventory3-api client-id-enforcement 1.3.3 --config '{
  "credentialsOriginHasHttpBasicAuthenticationHeader": "customExpression",
  "clientIdExpression": "#[attributes.headers['client_id']]",
  "clientSecretExpression": "#[attributes.headers['client_secret']]"
}'
```

長い JSON は `--config @policy.json` でファイルからも渡せます (秘密の値はファイルに書かない)。

---

## 3. 付ける前に知っておく 4 つ

1. **ポリシーは適用しただけでは効きません。** 経路にゲートウェイがいなければ、API は無防備なままです。
   詳しくは `bash scripts/plugin-root.sh knowledge/gotchas/api-manager.md` の最初の項目。
2. **実装資産は自動で選ばれます。** `client-id-enforcement` を付けると、Flex Gateway のインスタンスには
   `client-id-enforcement-flex` が入ります。`-flex` の方を自分で指定しない。
3. **そのゲートウェイが対応していないポリシーは付きません。** 失敗したらエラー本文を読む。
   同じ組織で動いている形に合わせるのが速い (`policy.sh list <他のインスタンス>`)。
4. **組織全体に自動で付くポリシー (automated policies) があります。** 自分が付けていないのに効いている、
   逆に外したのに効いている、のときはここを見る:
   ```bash
   bash scripts/anypoint-api.sh '/apimanager/api/v1/organizations/{org}/automated-policies'
   ```

---

## 4. 外し方

```bash
bash scripts/policy.sh list <インスタンス>              # policyId と、今の設定を控える
bash scripts/policy.sh remove <インスタンス> <policyId>  # 204 で外れる (2026-09-12 実測)
bash scripts/policy-check.sh <URL> ...                  # 守りが変わったので回し直す
```

- **外すと設定は消えます。**戻すには同じ設定で付け直すので、外す前に `list` の設定を控える。
- 一時的に止めたいときも外す (「無効にする」操作はこのスクリプトでは扱いません)。
- 設定だけ変えたいときは、外して付け直すのが確実です
  (API Manager には更新 `PATCH .../policies/{policyId}` もありますが、このプラグインでは未実測)。
- `order` は付けた順に 1, 2, ... と付きます。並べ替えは未実測なので、順序が要るときは
  **外して付け直す順番**で作る。

---

## 5. client-id 系は「契約」が要る

ポリシーが効いていても、**その `CLIENT_ID` がその API インスタンスと契約していなければ 401** です。

```bash
bash scripts/anypoint-api.sh '/apimanager/api/v1/organizations/{org}/environments/{env}/apis/<インスタンス ID>/contracts'
# {"total":0,"contracts":[]} なら契約が無い
```

契約が無ければ利用者アプリを作って契約します。作り方は
`bash scripts/plugin-root.sh knowledge/gotchas/api-manager.md` の「利用者アプリの作成」の行。

---

## やってはいけないこと

| やってはいけない | 代わりに |
|---|---|
| 設定キーを推測して `apply` する | `policy.sh config <assetId>` で見る (間違えても 201 が返るので気付けない) |
| `apply` が 201 だったことをもって「守れた」と報告する | `policy-check.sh` の exit 0 を根拠にする |
| `authorizations.yaml` を書き換えて許可を作る | 書くのは人。止まって理由を伝える |
| 画面 (API Manager の UI) を人に見てもらう | ここのコマンドで取れる。取れないときだけ `mule-guide` の 5 の手順で探す |
| `-flex` 付きの実装資産を指定する | テンプレート側の assetId を指定する (実装は自動) |
| 本番環境に付ける | 本番は人が手で行う (スクリプトも止まる) |

---

## 根拠

2026-09-12、flexGateway のインスタンス (Private Space の managed ゲートウェイ) で実測:
`find` (Exchange に 131 件)、`config` (schema.json から設定キー)、`list`、
`apply` → **201** (`header-injection` / 版の自動解決 / 実装資産の自動選択)、
`remove` → **204** (一覧から消え、元の状態に戻ることを確認)、
**誤ったキー (`{"nosuchkey":1}`) でも 201** が返ること、`policy.sandbox: denied` と本番系の環境名で
スクリプトが止まること。`client-id-enforcement` の適用 201 は inventory3-api T-007 (2026-09-11) の実測。
