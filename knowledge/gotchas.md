# 共有ナレッジ (全リポジトリに効く) — 索引

**これは索引です。ここを読んで、主題を 1 つだけ開く。`knowledge/gotchas/` を丸ごと読まない。**
実測した地雷の原文 (症状・根拠・何回どこで起きたか) は主題別に `knowledge/gotchas/<主題>.md` にあります。
**知っていれば試さなくて済むこと**の要約は `knowledge/mule-basics.md` (こちらは症状の原文と根拠を持つ側)。

`/mule-learn --share` の PR で増えます。追記先は主題の合うファイル。**根拠のない項目を足さない。**
各項目に「何回どこで起きたか」を必ず書く。主題が無ければ新しいファイルを作り、この表に 1 行足す。

**1 つの接続先 (DB 製品、ドライバ、ランタイム) で測った事実は、接続先の名前を本文に書く。**
「TIMESTAMP 列は String」と平叙で書いた項目が、実は Derby 1 件の実測で、Oracle では素の `Object`
だったため別プロジェクトで 500 になりました (v0.6.22 の直前まで残っていた)。**測った範囲を超えて
書くと、読んだ側は確かめずに従います。** 範囲が 1 接続先に閉じるなら `context/environment/` 側です。

**プラットフォーム操作 (API Manager、ポリシー、Exchange) は手探りの前に同梱の公式スキルを読む。**
`secure-api`、`apply-policy-to-api-instance`、`platform-assistant`。実例で遠回りした落とし穴のうち 3 件は既にそこに書いてあった (PR #2、2026-09-06)。

確認した版 (2026-09-05〜07): Mule 4.12.2 / MUnit 3.7.4 / APIkit 1.12.6 / mule-db-connector 1.16.3 /
mule-http-connector 1.10.0 / mule-maven-plugin 4.10.1 / Java 17 / CE。

## 症状から主題を選ぶ

| 主題 | ファイル | 件 | こういう症状のとき |
|---|---|---|---|
| プロジェクトとビルド | `gotchas/build.md` | 15 | 依存が取れない、起動しない、`requiredProduct`、Maven 401、JDK 違い、RAML がクラスパスに乗らない、JDBC jar が fat でない、**jar に秘密が混入**、**入れた hook がその日は効かない**、**group-id を他プロジェクトから写す**、**`mule-apikit-module` の足し忘れ** |
| 設定とプロパティ | `gotchas/config.md` | 4 | `${x.y}` を上書きできない、YAML の値の型、`p()`、**数値の項目に `SET_` で `NumberFormatException`** |
| MUnit | `gotchas/munit.md` | 15 | `mock-when` が効かない、カバレッジ、`target=`、`default` で牙が無い、**モックが型の不一致を隠す**、APIkit の振り分け flow 直叩き、**`munit:payload` に `output` を付けて `Stream Compatible`**、**main flow は flow-ref で振り分けられない** |
| エラー処理 | `gotchas/error-handling.md` | 6 | `on-error-continue` の再開位置、`<try>` の中の `error-handler`、`raise-error` できない型、`ANY` の枝 |
| APIkit と HTTP | `gotchas/apikit-http.md` | 3 | `requestPath` にベースパスが付く、`payload as String` で `Cannot coerce`、検証エラーの文面 |
| DB コネクタ | `gotchas/db.md` | 8 | SQL が属性で動かない、`db:update` の適用範囲、戻り値の形、**TIMESTAMP の型が DB で違う**、**Oracle の `ORA-12505` / 接続できるのに `ORA-00942`**、`affectedRows`、`payload[0]`、デッドロック |
| DataWeave | `gotchas/dataweave.md` | 4 | `dw validate -f`、`p()` の誤検知、予約語、**`as String` が `.0` を落とす** |
| 配備 (CloudHub 2.0 / Runtime Fabric) | `gotchas/deploy.md` | 7 | Exchange 経由必須、**1 コマンドで打つと 404**、公開 URL が付かない、properties が消える、RTF のログ、Flex に curl が届かない |
| API Manager とポリシー | `gotchas/api-manager.md` | 6 | ポリシー適用が効かない (**ゲートウェイで 401 でも upstream が公開なら素通し**)、autodiscovery が EE 要求、インスタンスの形、flexGateway の制約、RAML の Exchange publish、**Managed Flex Gateway の公開 URL (インスタンスに無い、ゲートウェイの側にある)** |

要約側 (`knowledge/basics/`) との対応は 1 対 1 ではありません。`apikit-http` の要約は `basics/flow.md`、
`api-manager` の要約は `basics/deploy.md` の中にあります。逆に `basics/flow.md` / `naming.md` / `kind.md` に
対応する gotchas はまだありません (実測が無い)。
