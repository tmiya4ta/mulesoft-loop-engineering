# fixtures — hook が「本当に弾くか」を確かめる最小の入力

`/mule-learn` の手順 4: **hook に昇格したものはテストを付ける。** それを踏む最小の入力をここに置き、
検査が exit 2 で弾くことを確認する。**弾けないなら昇格していない。**

台帳の `test-toothless` 6 件のうち 5 件が「検査自体が一度も走っていなかった」でした。
hook も同じで、書いた本人は「効いている」と思い込みます。だから入力を残して機械に確かめさせます。

| ファイル | 踏む指紋 | 期待 |
|---|---|---|
| `bad-db-sql-attribute.xml` | `db-sql-must-be-child-element` (台帳 T-003) | `mule-xml-shape.sh` が exit 2 |
| `bad-try-errorhandler-position.xml` | `try-errorhandler-position` (台帳 T-005) | `mule-xml-shape.sh` が exit 2 |
| `bad-subflow-errorhandler.xml` | sub-flow は error-handler を持てない (mule-core-common.xsd) | `mule-xml-shape.sh` が exit 2 |
| `ok-global-errorhandler.xml` | **弾いてはいけない形** (ルート直下の error-handler) | exit 0 |

確認: `bash scripts/fixtures-check.sh`
