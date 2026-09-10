---
name: mule-init
description: 今いるリポジトリを MuleSoft ループエンジニアリング用に初期化する。CLAUDE.md、tasks/、samples/、api/、scripts/、.claude/settings.json をテンプレートから配置する。既存の Mule プロジェクトにも新規にも使える。
argument-hint: "[--kind api|batch|mcp|a2a] [--layer system|process|experience] [--name <api-name>]"
---

`${CLAUDE_PLUGIN_ROOT}/template/` の内容を今のリポジトリ直下に配置します。Mule アプリは HTTP API 以外にも、
バッチ処理、MCP サーバー、A2A (Agent-to-Agent) エージェントとして作れる。何を作るかで以降の手順が変わるので、
最初にそれを決める。

## 手順
1. `git rev-parse --show-toplevel` でリポジトリ直下を確認する。git 管理外なら `git init` してから進める (聞かない。取り消せる)。
2. 引数に `--kind` と `--name` が無ければ、`context/decisions.yaml` の `kind` と `api.purpose` を見る。それも無ければ AskUserQuestion **1 回** で両方まとめて聞く (人に聞くのはここだけ)。
   - kind の選択肢:
     1. 「HTTP で呼ばれる API を作る (RAML/APIkit) → api」(推奨。このプラグインが最も手厚く面倒を見る)
     2. 「まとまったデータを定期的に処理する Batch Job を作る → batch」
     3. 「LLM やエージェントにツールとして使わせる MCP サーバーを作る → mcp」
     4. 「他のエージェントと A2A で連携する Agent を作る (Agent Fabric) → a2a」
   - **`kind: a2a` を選んだら、ここで終える。** 「A2A (Agent Network) は `agentNetwork.yaml` / `.agent` ファイルという別のプロジェクト形式で、pom.xml を持つ通常の Mule アプリではありません。`agent-network` スキルと `deploy-agent-network-v1` / `deploy-agent-network-v2` スキルが専門なので、そちらを使ってください」と伝え、以降の手順 (Mule プロジェクト作成、MUnit 追加など) は行わない。
2b. `kind` が `api` のときだけ、`--layer` が無ければ `context/decisions.yaml` の `layer` を見て、無ければ続けて AskUserQuestion で 1 問聞く (人に聞くのはここまで)。
   - layer の選択肢: 「外部システム (SAP / DB / SaaS) を包む → system」「複数の system を組み合わせて業務の 1 手順にする → process」「画面や特定の利用者向けに形を整える → experience」。専門用語より用途の説明を前に出す。
   `batch` / `mcp` は層分けの対象外。layer は空のままにする (人に聞かない)。
3. **Mule プロジェクトが無ければ作る (`kind: api` / `batch` / `mcp` 共通)。** `pom.xml` が無い場合、Studio / ACB と同じ構成 (mule-maven-plugin、Exchange と MuleSoft のリポジトリ、mule-artifact.json) を持つ骨格を CLI で作る。手で pom を書くと Maven のライブラリ取得に失敗するので、必ずこの経路を使う。
   `--dependencies` は `kind` で変える。**HTTP コネクタは `kind: api` のときだけ渡す。** `kind: mcp` は MCP コネクタ、`kind: batch` は DB / SaaS など実際に使うものだけを渡し、使わない HTTP コネクタを既定で足さない。
   ```bash
   # kind: api
   NODE_NO_WARNINGS=1 anypoint-cli-v4 dx mule project create <name> --group-id <組織 ID> --mule-version 4.12.2 \
     --dependencies "org.mule.connectors:mule-http-connector:1.10.0"
   # kind: mcp (HTTP は付けない。GAV は describe-connector か Exchange で確認してから使う)
   # kind: batch (依存は要件次第。何もコネクタを使わないなら --dependencies 自体省略してよい)
   ```
   生成物は `<name>/` に入るので、リポジトリ直下に移す (`mv <name>/* <name>/.[!.]* . 2>/dev/null; rmdir <name>`)。
   CLI が無い場合 (`anypoint-cli-v4 dx mule --help` が失敗) は `npm i -g anypoint-cli-v4 && anypoint-cli-v4 plugins:install @salesforce/anypoint-cli-dx-mule-plugin` を案内する。MCP `create_mule_project` でも同じものが作れる。
   **版は 4.10.1 以降にする (既定 4.12.2)。** 4.9.0 は `mule-runtime-impl-no-services-bom` が公開リポジトリに無く、
   `ee:transform` を 1 つ書いた時点で MUnit が `Cannot create embedded container` で動かなくなる (`knowledge/gotchas/build.md` 参照)。
   **コネクタの GAV は推測せず、`anypoint-cli-v4 dx mule describe-connector` か Exchange で確かめる。** MCP コネクタの GAV もここで確認する (このプラグインは既知の版を決め打ちしない)。
   **`--group-id` は Anypoint の組織 ID (UUID) です。人に聞くか
   `anypoint-cli-v4 account business-group list` で取ります。**
   **このマシンにある他のプロジェクトの pom から写さないこと。** 組織が違えば Exchange への publish が
   落ちるか、**別の組織に publish する事故**になります。CH2 / RTF は Exchange 経由でしか置けず、
   Exchange のアセットは groupId = 組織 ID という決まりなので、ここを間違えると後段が全部崩れます。
   分からなければ**空のまま止まって人に聞く**。推測で埋めない。

3ab. **mule-maven-plugin の版を直す。** `bash scripts/fix-plugin-version.sh` を実行する。
   CLI は 4.7.0 を固定するが Mule 4.12 系とは非互換で、`NoSuchMethodError:
   MuleRuntimeFeature.isEnabled` でビルドが通らない。
3aa. **前提の置き場所を作る。** `context/` (requirements / environment / deployment / `decisions.yaml`)、`budget.yaml`、`context/deployment/authorizations.yaml`、`knowledge/` を配置し、**利用者に「資料をここに置いてください」と具体的なパスを伝え、`context/requirements/_template.md` をコピーして埋めればよいこと、System 層 (`kind: api` かつ `layer: system`) や DB を直接触る `batch` ならデータモデル (DDL かオブジェクト定義) が必須であることを添える**。URL しか無い場合は `context/sources.yaml` に書いてもらう。
3b. **MUnit を足す。** 生成直後の pom には MUnit が無いので `scripts/add-munit.sh` を実行する (設定済みなら何もしない)。
3c. template/ の各ファイルをコピーする (**列挙せず丸ごと**。プラグインに検査が増えても新規プロジェクトは自動で揃う)。**既にあるファイルは上書きしない**。
    **既存のプロジェクトはこれで追随しません。** プラグインを更新したら `scripts/` が置いて行かれるので、
    `preflight.sh` が波の前に照合して名指しで言います (`cp <プラグイン>/template/scripts/*.sh scripts/` で直る)。CLAUDE.md が既にある場合は末尾に template/CLAUDE.md の内容を追記し、冒頭にマーカー `<!-- mule-loop -->` を付ける。
4. CLAUDE.md の `kind:`、`layer:` (`kind: api` のときだけ。それ以外は空のまま)、`name:` を埋める。
5. `mvn -v`、`dw --version`、`xmllint --version`、`anypoint-cli-v4 dx mule --help` の有無を確認し、無いものを表にして知らせる。
5aa. `bash scripts/munit-coverage-mode.sh` を実行する。EE ランタイムが取れれば MUnit のカバレッジ 100% ゲートを pom に入れ、取れなければ入れず、`scripts/coverage-check.sh` による構造チェックが保証になることを利用者に伝える。
5b. `mvn -q clean package -DskipTests` を 1 回流し、ライブラリ取得が通ることを確かめる。失敗したら `~/.m2/settings.xml` の Exchange 認証 (Enterprise コネクタを使う場合) を疑い、docs/mulesoft-tools.md の「プロジェクト作成」を案内する。
5c. **スキーマ索引を作る。** `bash scripts/schema-index.sh` を実行する。`~/.m2` の jar から、この
   プロジェクトが解決した版のコネクタ定義 (パラメータ名と説明) とランタイム XSD を
   `reference/mule-schema/` に抜き出し、`INDEX.md` を書く。実行エージェントがコネクタの
   要素名やパラメータ名を推測しないための地の情報で、**版が必ず一致する**のが手書きとの違い。
   5b が失敗していると `~/.m2` が埋まっていないので何も取れない。その場合は exit 2 と
   「未解決」の一覧が出るだけなので、5b を直してから再実行する。**生成物は 6b の初期コミットに含める**
   (worktree は origin/main から切られるため、コミットしないと実行エージェントに届かない)。

6. `.mcp.json` はコピーしない (MCP はプラグイン側で有効になる)。聞かない。
6b. **初期コミットを作る。** `git add -A && git commit -m "mule-loop: init"`。worktree 隔離はコミットが 1 つも無いと `Failed to resolve base branch "HEAD"` で起動しない (PR #4)。`.gitignore` に `target/` と `.claude/worktrees/` があることを先に確認する。
7. 最後に「現在地 / 次にすること / そのあと」の 3 ブロックで締める。次にすることは
   「`context/requirements/` に資料を置く (パスを具体的に示す)」か、資料が無いなら
   「`/mule-start <作りたいこと>`」の 1 つだけにする。
   `kind: batch` / `mcp` のときは「そのあと」に一言足す: 「`knowledge/basics/kind.md` (Batch / MCP / A2A) を読んでください。
   まだこのプラグイン専用の reference/ 雛形が無く、困ったら gotchas → スキル → マニュアルの順で進めることになります」。
