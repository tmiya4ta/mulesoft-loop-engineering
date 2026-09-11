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

## 【未解決】Managed Flex Gateway (Private Space) の実際の公開URLがAPIから分からない
target が `targetType: private-space` かつ `kind: managed` のとき (`getGatewayTargets` で
`kind: "managed"` と出る)、API インスタンスを作成・配備 (`type: HY`、上の表の形) しても、
**外部から実際に叩けるホスト名がどのAPIレスポンスにも出てこない。**

試して失敗したもの (inventory3-api T-007, 2026-09-11):
- Private Space の `network.dnsTarget` (例 `pnwfdv.jpn-e1.cloudhub.io`) をそのまま使う → 404
  (ワイルドカードは解決するが、この API 用のルートが無い)
- `<targetName>.<dnsTarget>` / `<apiId>.<dnsTarget>` などの推測 → 同じく 404
- Private Space の `network.inboundStaticIps` へ配備した port (8081/8082) で直接接続 → タイムアウト
  (`managedFirewallRules` が 80/443/30500-32500 しか inbound を許可していない。個別 port は
  ファイアウォールで塞がれている)

**現時点の回避策:** Runtime Manager の UI (`https://anypoint.mulesoft.com/cloudhub/#/console/home/managed-gateways/<targetId>/dashboard`) を人に開いてもらい、実際の公開 URL を教えてもらう。
API 経由で解決する方法が分かったら、この項目を書き換えて `【未解決】` を外すこと。
