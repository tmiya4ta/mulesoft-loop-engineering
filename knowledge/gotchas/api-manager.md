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
