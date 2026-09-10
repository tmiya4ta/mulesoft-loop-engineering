# ビルドと配備

要約 (1 項目 = 1 事実)。印は `[G]` 実測 / `[S]` スキル / `[K]` K ファイル / `[D]` 公式 / `[reference]` 写経元。
根拠の原文は `../gotchas.md` の索引から、他の主題と対象の版は `../mule-basics.md` から。

- ローカル検証は速い順: `dw validate` → `mvn -q clean test -Dmunit.test=<file>` → `mvn -q clean test` → `mvn -q clean package -DskipTests` (XSD 検証はここで初めて走る)。[reference]
- CH2 / RTF は **Exchange 経由のみ**。`mvn clean deploy -DmuleDeploy` (`scripts/deploy-config.sh` が pom に設定を入れる)。Exchange は同一版を上書きできないので **配備ごとに `scripts/bump-version.sh`**。[G]
- CH2 の公開 URL は `--publicEndpoints` では付かない。`scripts/ch2-public-url.sh` (Application Manager API の `generateDefaultPublicUrl`)。`runtime-mgr application modify` は **properties を消す**。[G]
- RTF はコンソールログが既定で無効。`KubernetesTemplate` (`ENABLE_CONSOLE_LOG: "true"`、名前は `mule-application`、namespace `rtf`) を作って再配備。[S]
- API Manager のポリシーは **適用しただけでは効かない** (201 が返っても経路にゲートウェイがいない)。Basic endpoint (autodiscovery、EE 必須) か Proxy (Flex) を選び、`scripts/policy-check.sh` (認証なし 401、あり 2xx) で判定する。[G]
- `~/.m2/settings.xml` には Maven Central と `anypoint-exchange-v3` (Connected App: `~~~Client~~~` / `<id>~?~<secret>`) が要る。EE の Nexus は資格情報が無ければコメントアウト。401 は `.classpath` の EE コネクタ参照か EE リポジトリの認証欠け。[S]
