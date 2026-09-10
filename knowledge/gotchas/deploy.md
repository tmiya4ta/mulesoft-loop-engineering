# 配備 (CloudHub 2.0 / Runtime Fabric) (実測した地雷)

`/mule-learn` の追記先。**根拠のない項目を足さない。**各項目に「何回どこで起きたか」を書き、
追記したら `../gotchas.md` の索引の件数も直す (`scripts/knowledge-index-check.sh` が検査)。

## CloudHub 2.0 は Exchange 経由でしか配備できない
jar を直接上げる口が無い。CH1 との一番大きな違い。mule-maven-plugin 経由でも
`404 Failed to retrieve artifact information from Exchange` で弾かれる。

そのため **`groupId` を組織 ID にする必要がある** (Exchange の資産の要件)。
`com.mycompany` のままでは公開できない。組織内の既存資産を見れば形が分かる。
`version` も上げ続ける必要がある。Exchange は同一版を上書きできない。
根拠: T1 organization への配備で実測 (2026-09-06)。

## `mvn clean deploy -DmuleDeploy` を 1 コマンドで打つと Exchange の 404 で必ず落ちる

**症状**: `Failed to retrieve artifact information from Exchange. Reason: 404 There is no asset
matching given parameters.`

**原因**: `muleDeploy` が、**まだ publish されていないアセットを先に参照する**。

**直し方**: 2 段階に分ける。
```bash
mvn clean deploy          # 1 段目: Exchange に publish するだけ
mvn deploy -DmuleDeploy   # 2 段目: publish 済みのアセットを配置する (clean を付けない)
```
2 段目に `clean` を付けると成果物が消えて publish からやり直しになる。

**同じ 404 が `<businessGroupId>` 欠けでも出る。** 無いと認証トークンの**既定組織 (Root)** を
参照するため、アセットが見つからない。`cloudhub2Deployment` に組織 ID を明示する
(`scripts/deploy-config.sh` が pom の `groupId` から入れる)。

根拠: inventory2-api で実測 (2026-09-09)。**このプラグインの `mule-deploy` の手順が
1 コマンドで書いてあったため、手順どおりにやると必ず落ちた** (v0.6.27 で 2 段階に直した)。

---

## CloudHub 2.0 の公開エンドポイントは `--publicEndpoints` では付かない
`anypoint-cli-v4 runtime-mgr application modify --publicEndpoints <host>` は
成功を返すが `access: internal` のまま変わらない。ホスト名だけでも
`https://` 込みの完全な URL でも同じ。

実体は `deploymentSettings.generateDefaultPublicUrl` で、CLI からは立てられない。
Application Manager の API を直接 PATCH する。

```
PATCH /amc/application-manager/api/v2/organizations/{org}/environments/{env}/deployments/{id}
{"target":{"targetId":"...","provider":"MC","replicas":1,
           "deploymentSettings":{"generateDefaultPublicUrl":true,"http":{"inbound":{"pathRewrite":"/"}}}}}
```
根拠: CH2 private space への配備で実測 (2026-09-06)。

## `runtime-mgr application modify` は properties を消す
`--property` / `--secureProperty` を付けずに `modify` を打つと、既に設定してある
アプリケーションプロパティが **空になる**。公開エンドポイントやレプリカ数だけを
変えたつもりが、DB の資格情報ごと飛ぶ。`modify` のたびに付け直す。

版を上げる `--assetVersion` は `Provided GAV is either incomplete or invalid` で
落ちる。`--groupId` を明示しても同じ。API の PATCH で
`application.ref.version` を書き換えるのが確実。
根拠: CH2 への再配備で 2 回とも実測 (2026-09-06)。

## RTF はコンソールログが既定で無効
`kubectl logs` でアプリのログを見るには `KubernetesTemplate` (名前は `mule-application` 固定、namespace `rtf`) で `ENABLE_CONSOLE_LOG: "true"` を立て、再配備する。
Anypoint Monitoring を使うと自動で無効化されることがある。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## RTF のアプリに Flex Gateway から届かせるには LoadBalancer サービスが要る
Flex Gateway が RTF 上の Mule アプリへルーティングする経路は、アプリを配備しただけでは通らない。
`type: LoadBalancer` の Service を立て (`selector` は RTF アプリのラベル、`port`/`targetPort` は
アプリの listener ポート)、`kubectl get svc` で EXTERNAL-IP を確認し、**API Manager の API インスタンスの
Implementation URI にその IP を書く** (`http://<EXTERNAL-IP>:8081/`)。
疎通しないときは配備ではなくここを疑う。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。

## Flex Gateway に curl が届かないときは IPv6 を疑う (`curl -4`)
環境によっては `localhost` が IPv6 (`::1`) に解決され、Flex Gateway への接続が失敗する。
**`curl -4` で IPv4 を明示する**と通る。ゲートウェイの設定によっては `Host` ヘッダーも要る
(`curl -4 -k -H "Host: mule-dev.com" https://localhost:1443/api/...`)。
smoke-check が落ちたとき、アプリやポリシーを疑う前にここを 1 回試す。
根拠: mulesoft-app-development スキル (利用者の過去の実測)。
