# context/ — ループに与える前提

`/mule-start` は最初にここを読む。**空のまま始めない。** 勝手に想像で進めると時間を無駄にする。

| 置き場所 | 何を入れるか |
|---|---|
| `requirements/` | 要件、業務フロー、画面仕様、既存 API の資料。PDF / Markdown / スクショ何でも |
| `environment/` | Mule runtime 版、Java 版、接続先 (DB / Salesforce / SAP) の URL と認証方式、コネクタ版 |
| `deployment/` | デプロイ先の組織 ID、環境 ID、種別 (Sandbox / Production) |

ファイルを置いたら `sources.yaml` にパスか URL を書く。資料が無い項目は `unknown` にする。
`unknown` の環境情報は `/mule-start` が自分で調べ、根拠つきで `environment/resolved.md` に書く。
