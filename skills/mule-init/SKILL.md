---
name: mule-init
description: 今いるリポジトリを MuleSoft ループエンジニアリング用に初期化する。CLAUDE.md、tasks/、samples/、api/、scripts/、.claude/settings.json をテンプレートから配置する。既存の Mule プロジェクトにも新規にも使える。
argument-hint: "[--layer system|process|experience] [--name <api-name>]"
---

`${CLAUDE_PLUGIN_ROOT}/template/` の内容を今のリポジトリ直下に配置します。

## 手順
1. `git rev-parse --show-toplevel` でリポジトリ直下を確認する。git 管理外なら `git init` を提案してから進める。
2. 引数に `--layer` と `--name` が無ければ、`context/decisions.yaml` の `layer` と `api.purpose` を見る。それも無ければ AskUserQuestion **1 回** で両方まとめて聞く (人に聞くのはここだけ)。
   - layer の選択肢: 「外部システム (SAP / DB / SaaS) を包む → system」「複数の system を組み合わせて業務の 1 手順にする → process」「画面や特定の利用者向けに形を整える → experience」。専門用語より用途の説明を前に出す。
3. **Mule プロジェクトが無ければ作る。** `pom.xml` が無い場合、Studio / ACB と同じ構成 (mule-maven-plugin、Exchange と MuleSoft のリポジトリ、mule-artifact.json) を持つ骨格を CLI で作る。手で pom を書くと Maven のライブラリ取得に失敗するので、必ずこの経路を使う。
   ```bash
   NODE_NO_WARNINGS=1 anypoint-cli-v4 dx mule project create <name> --group-id <group> --mule-version 4.12.2 \
     --dependencies "org.mule.connectors:mule-http-connector:1.10.0"
   ```
   生成物は `<name>/` に入るので、リポジトリ直下に移す (`mv <name>/* <name>/.[!.]* . 2>/dev/null; rmdir <name>`)。
   CLI が無い場合 (`anypoint-cli-v4 dx mule --help` が失敗) は `npm i -g anypoint-cli-v4 && anypoint-cli-v4 plugins:install @salesforce/anypoint-cli-dx-mule-plugin` を案内する。MCP `create_mule_project` でも同じものが作れる。
   **版は 4.10.1 以降にする (既定 4.12.2)。** 4.9.0 は `mule-runtime-impl-no-services-bom` が公開リポジトリに無く、
   `ee:transform` を 1 つ書いた時点で MUnit が `Cannot create embedded container` で動かなくなる (knowledge/gotchas.md 参照)。
   コネクタの GAV は推測せず、`anypoint-cli-v4 dx mule describe-connector` か Exchange で確かめる。
3ab. **mule-maven-plugin の版を直す。** `bash scripts/fix-plugin-version.sh` を実行する。
   CLI は 4.7.0 を固定するが Mule 4.12 系とは非互換で、`NoSuchMethodError:
   MuleRuntimeFeature.isEnabled` でビルドが通らない。
3aa. **前提の置き場所を作る。** `context/` (requirements / environment / deployment / `decisions.yaml`)、`budget.yaml`、`context/deployment/authorizations.yaml`、`knowledge/` を配置し、**利用者に「資料をここに置いてください」と具体的なパスを伝える**。URL しか無い場合は `context/sources.yaml` に書いてもらう。
3b. **MUnit を足す。** 生成直後の pom には MUnit が無いので `scripts/add-munit.sh` を実行する (設定済みなら何もしない)。
3c. template/ の各ファイルをコピーする。**既にあるファイルは上書きしない**。CLAUDE.md が既にある場合は末尾に template/CLAUDE.md の内容を追記し、冒頭にマーカー `<!-- mule-loop -->` を付ける。
4. CLAUDE.md の `layer:` と `name:` を埋める。
5. `mvn -v`、`dw --version`、`xmllint --version`、`anypoint-cli-v4 dx mule --help` の有無を確認し、無いものを表にして知らせる。
5aa. `bash scripts/munit-coverage-mode.sh` を実行する。EE ランタイムが取れれば MUnit のカバレッジ 100% ゲートを pom に入れ、取れなければ入れず、`scripts/coverage-check.sh` による構造チェックが保証になることを利用者に伝える。
5b. `mvn -q clean package -DskipTests` を 1 回流し、ライブラリ取得が通ることを確かめる。失敗したら `~/.m2/settings.xml` の Exchange 認証 (Enterprise コネクタを使う場合) を疑い、docs/mulesoft-tools.md の「プロジェクト作成」を案内する。
6. `.mcp.json` はコピーしない (MCP はプラグイン側で有効になる)。聞かない。
7. 最後に「現在地 / 次にすること / そのあと」の 3 ブロックで締める。次にすることは
   「`context/requirements/` に資料を置く (パスを具体的に示す)」か、資料が無いなら
   「`/mule-start <作りたいこと>`」の 1 つだけにする。
