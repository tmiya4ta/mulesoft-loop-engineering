# context/ — ループに与える前提

`/mule-start` は最初にここを読む。**空のまま始めない。** 勝手に想像で進めると時間を無駄にする。

| 置き場所 | 何を入れるか |
|---|---|
| `requirements/` | 要件、業務フロー、画面仕様、既存 API の資料。PDF / Markdown / スクショ何でも |
| `environment/` | Mule runtime 版、Java 版、接続先 (DB / Salesforce / SAP) の URL と認証方式、コネクタ版 |
| `decisions.yaml` | 決めごと。先に埋めた項目は聞かれない。空欄は `/mule-start` が最初に 1 回まとめて聞く |
| `deployment/` | `authorizations.yaml` (置いてよいか) と `sandbox.yaml` (どこに置くか: cloudhub2 / rtf、環境名、target) |

ファイルを置いたら `sources.yaml` にパスか URL を書く。資料が無い項目は `unknown` にする。
`unknown` の環境情報は `/mule-start` が自分で調べ、根拠つきで `environment/resolved.md` に書く。
