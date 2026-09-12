# API Manager とポリシー (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

## API Manager のポリシーは「適用」だけでは効かない
ポリシーを適用して 201 が返り、API Manager の一覧にも出るのに、**API は無防備なまま**という
状態になる。経路にゲートウェイがいないため。API インスタンスの `status` が
`unregistered` で `deployment` が `null` なら、そのポリシーは何も守っていない。

施行させる道は 2 つ。**どちらを選ぶかで必要な設定がまるごと変わる。**

| 型 | 何が要るか |
|---|---|
| **Basic endpoint** | Mule アプリ側に autodiscovery (`api-gateway:autodiscovery`) の設定が要る |
| **Proxy** | インスタンスの target URL を **アプリの内部エンドポイント** にし、**アプリの公開エンドポイントを消す**。外部からはプロキシに入る |

適用しただけの状態を放置しないこと。**「ポリシーが付いている」という表示と実際の保護が
食い違うのは、ポリシーが無いより危険。**
根拠: CloudHub 2.0 の Mule アプリに client-id-enforcement を掛ける過程で実測 (2026-09-06)。
適用は 201、認証なしのリクエストは 200 のまま通った。
2 回目 (inventory3-api T-007、2026-09-12): Proxy 型で**ゲートウェイ経由は 401 になった**が、upstream が
アプリの**公開** URL のままで、そちらを認証なしで叩くと `GET /inventory` が 200。**ゲートウェイで 401 が
出ても、迂回路が開いていれば守れていない。** `scripts/gateway-public-url.sh` は upstream に外から届くかを
見て注意を出す。

## ポリシーの設定 (configurationData) は適用時に検証されない。誤ったキーでも 201
`POST .../apis/{id}/policies` は、**そのポリシーに存在しないキーを渡しても 201 を返す**
(`{"nosuchkey":1}` で実測)。設定が効いていないポリシーが「適用済み」として一覧に並ぶ。

だから **201 は「守れた」の根拠にならない**。設定キーは推測せず、ポリシー資産のスキーマから取る:

```bash
bash scripts/policy.sh config client-id-enforcement    # 設定キー / 必須 / 選べる値
bash scripts/policy.sh apply <インスタンス> <assetId> --config '<JSON>'
bash scripts/policy-check.sh <URL> client-id <path>    # ← 効いたかはこれで決める
```

版を省くと Exchange の最新が使われ、実装資産はゲートウェイに合わせて自動で選ばれる
(`client-id-enforcement` 1.3.3 → `client-id-enforcement-flex` 1.2.0)。`-flex` を自分で指定しない。
外すのは `policy.sh remove <インスタンス> <policyId>` (204。設定は消えるので外す前に `list` で控える)。
根拠: flexGateway のインスタンスで apply 201 / remove 204 / 誤キー 201 を実測 (2026-09-12)。
手順は `bash scripts/plugin-root.sh --skill mule-policy`。

## autodiscovery は EE の成果物が要る
`com.mulesoft.mule.modules:mule-api-gateway-module` は EE 側にあり、
Exchange の entitlement が無い環境では **Maven でも解決できない** (1.3.0 / 1.4.0 / 1.5.0 /
1.6.0 を試して全滅)。`ee:transform` と同じ壁。

EE が使えない環境では Basic endpoint 型は選べない。Proxy 型 (Omni Gateway) を使う。
根拠: 4 版を `mvn dependency:get` で試して全滅 (2026-09-06)。

## API インスタンスは「その組織で動いている形」に合わせる
`anypoint-cli-v4 api-mgr api manage --type raml --deploymentType cloudhub2` で作ると
`technology: mule3` のインスタンスができ、配備が通らない。

**手探りする前に、同じ組織で既に配備されている API インスタンスを読むこと。**
`GET /apimanager/api/v1/organizations/{org}/environments/{env}/apis/{id}` の
`technology` `endpoint.apiGatewayVersion` `deployment.type` `deployment.targetName` を
写せば、その環境で通る形が分かる。

実例では既存 3 本がすべて `flexGateway` / `HY` / `gatewayVersion 1.13.4` / target `ft1` で、
同じ形にしたら 201 で通った。CH2 プロキシ (`type: CH2`) は同じ組織で 500 のままだった。
根拠: 3 度作り直してようやく通った (2026-09-06)。

## flexGateway のインスタンス作成と配備の細かい制約
API を直接叩いて作る場合の必須の形。CLI では作れない組み合わせがある。

| 項目 | 値 | 間違えたときの症状 |
|---|---|---|
| `endpoint.muleVersion4OrAbove` | **`null`** | `Argument "muleVersion4OrAbove" is invalid for ... flexGateway` |
| `endpoint.validation` | **`NOT_APPLICABLE`** | `Validation status is invalid for the provided proxy/mule version` |
| `gatewayVersion` (配備) | ゲートウェイの版 (例 `1.13.4`)。**ランタイムの版ではない** | `Deployment blocked due to incompatible Proxy Version` |
| `endpoint.proxyUri` の港 | ゲートウェイが開けている港のみ (例では 8081 / 8082)。**パスで分ける** | `Proxy must be deployed in a port that is available` |
| 利用者アプリの作成 | `POST /exchange/api/v2/organizations/{org}/applications?apiInstanceId=<id>` | `A target apiInstanceId or groupInstanceId is required` |

根拠: 上記すべて実測 (2026-09-06)。

## flexGateway インスタンスを作る前に、RAML を Exchange に置く (rest-api アセット)
`spec.groupId/assetId/version` が指す先は Exchange 上の **RAML アセット** (`type: rest-api`)。
Mule アプリを publish した Exchange アセット (`mule-application`) とは別物で、流用できない。

公式ポータルの API Manager OAS は `createApiInstance` の multipart body のフィールドを
明示しておらず (`file` としか書いていない)、RAML 単体を publish する形は別の経路で確認する必要がある。
依存の無い単一 RAML なら、Exchange API v2 に直接 multipart で投げれば済む (Maven プロジェクトを
作らなくてよい):

```bash
curl -H "Authorization: bearer $TOKEN" -H 'x-sync-publication: true' \
  -F 'name=<表示名>' -F 'description=<説明>' \
  -F 'properties.mainFile=<ファイル名>.raml' -F 'properties.apiVersion=v1' \
  -F "files.raml.raml=@<ファイル名>.raml" \
  "https://anypoint.mulesoft.com/exchange/api/v2/organizations/{org}/assets/{groupId}/{assetId}/{version}"
```
201 で `"type":"rest-api"` が返れば成功。依存 (RAML フラグメント) があるときは
`files.raml.raml=@x.raml` の代わりに `exchange_modules/` を含めた zip を
`files.raml.zip=@raml.zip` で送る (`properties.mainFile` はエントリの RAML ファイル名のまま)。
根拠: `mulesoft-labs/exchange-documentation-samples` の `raml-fragment/README.md` と
`raml-with-dependencies/README.md` に実例がある。inventory3-api T-007 で実測して通った (2026-09-11)。

## Managed Flex Gateway に置いた API の公開 URL は、インスタンスではなくゲートウェイの側にある
API Manager のインスタンスには upstream (`endpoint.uri`) とゲートウェイ内の待ち受け
(`endpoint.proxyUri`、例 `http://0.0.0.0:8081/inventory3-api/`) しか無く、**外からの URL は載っていない。**
載っているのは **Gateway Manager API の `getGatewayById`** (`/gatewaymanager/api/v1/organizations/{org}/environments/{env}/gateways/{gatewayId}`、
`{gatewayId}` はインスタンスの `deployment.targetId`):

| 項目 | 例 | 意味 |
|---|---|---|
| `configuration.ingress.publicUrl` (`endpoints[]` の `access: external`) | `https://ft1-xxxxxx.<dnsTarget>` | ゲートウェイの公開 URL |
| `configuration.ingress.internalUrl` (`access: internal`) | `https://ft1-xxxxxx.internal-<dnsTarget>` | 同じ Private Space の内側から |
| `portConfiguration.ingress.port` | `8081` | **公開 URL が届く港** |
| `portConfiguration.egress.port` | `8082` | 内側 (`clusterUrl`、例 `http://ft1:8082/`) からだけ届く港。Agent Network の接続が使う |

**API の URL = 公開 URL + proxyUri のパス** (末尾の `/` を外し、後ろにリソースを付けて叩く)。
proxyUri の港が ingress の港のときだけ外から届く。まとめて出すのが `scripts/gateway-public-url.sh`:

```bash
bash scripts/gateway-public-url.sh inventory3-api      # instanceLabel / assetId / インスタンス ID のどれでも
# → https://ft1-xxxxxx.<dnsTarget>/inventory3-api     (これを policy-check.sh の 1 つ目に渡す)
```

| 叩いたもの | 結果 |
|---|---|
| `<公開 URL>/inventory3-api/inventory` (認証なし) | 401 `{"error":"Client ID is not present"}` (ポリシーが応答している) |
| `<公開 URL>/inventory3-api` (末尾の `/` 無し) / ゲートウェイに無いパス | 404 |
| egress (8082) に置いた API を公開 URL で | 404 |
| self-managed のゲートウェイ (`kind: selfManaged`) を `getGatewayById` で | 404 `AMC Error: Deployment not found`。URL は動かしている側が決める |

**以前はここを【未解決】として、人に Runtime Manager の画面を見てもらっていた。** 試したのは
Private Space の `network.dnsTarget` / `inboundStaticIps` (ゲートウェイではなく土台の方) とホスト名の
推測だけで、36 本ある公式 API のうち Gateway Manager を見ていなかった。
`bash scripts/portal-search.sh publicUrl` なら 1 手で 2 本に絞れ、`getGatewayById` と叩く行まで出る。
**「API から取れない」と書く前に `portal-search.sh` で項目名を引くこと。** 根拠に `portal-search.sh` の
無い【未解決】は `scripts/knowledge-index-check.sh` が弾く。
根拠: managed のゲートウェイ (Private Space、1.13.4) で上の表をすべて実測 (2026-09-12)。
inventory3-api T-007 で 2026-09-11 に【未解決】と記録されたもの (PR #9) を、同じ環境で解いた。
