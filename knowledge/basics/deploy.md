# ビルドと配備

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- ローカル検証は速い順: `dw validate` → `mvn -q clean test -Dmunit.test=<file>` → `mvn -q clean test` → `mvn -q clean package -DskipTests` (XSD 検証はここで初めて走る)。[reference]
- CH2 / RTF は **Exchange 経由のみ**。`mvn clean deploy -DmuleDeploy` (`scripts/deploy-config.sh` が pom に設定を入れる)。Exchange は同一版を上書きできないので **配備ごとに `scripts/bump-version.sh`**。[G]
- CH2 の公開 URL は `--publicEndpoints` では付かない。`scripts/ch2-public-url.sh` (Application Manager API の `generateDefaultPublicUrl`)。`runtime-mgr application modify` は **properties を消す**。[G]
- RTF はコンソールログが既定で無効。`KubernetesTemplate` (`ENABLE_CONSOLE_LOG: "true"`、名前は `mule-application`、namespace `rtf`) を作って再配備。[S]
- API Manager のポリシーは **適用しただけでは効かない** (201 が返っても経路にゲートウェイがいない)。Basic endpoint (autodiscovery、EE 必須) か Proxy (Flex) を選び、`scripts/policy-check.sh` (認証なし 401、あり 2xx) で判定する。Proxy 型で upstream がアプリの**公開** URL のままなら迂回できる。[G]
- Managed Flex Gateway に置いた API の公開 URL は **API インスタンスに無い**。ゲートウェイの `getGatewayById` の `configuration.ingress.publicUrl` + proxyUri のパス (proxyUri の港が `portConfiguration.ingress.port` のときだけ外から届く)。`scripts/gateway-public-url.sh <インスタンス>`。[G]
- Anypoint にある値 (URL、ID、状態) は、人に画面を見てもらう前に `scripts/portal-search.sh '<項目名>'` でどの API が返すかを引き、`scripts/anypoint-api.sh '<パス>'` で GET する。仕様に書かれていない項目もある (Private Space の `dnsTarget`) ので、外れたら一覧か詳細の GET を `--find <項目名>` で探す。[G]
- `~/.m2/settings.xml` には Maven Central と `anypoint-exchange-v3` (Connected App: `~~~Client~~~` / `<id>~?~<secret>`) が要る。EE の Nexus は資格情報が無ければコメントアウト。401 は `.classpath` の EE コネクタ参照か EE リポジトリの認証欠け。[S]
