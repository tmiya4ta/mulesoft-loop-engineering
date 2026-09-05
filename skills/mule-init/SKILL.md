---
name: mule-init
description: 今いるリポジトリを MuleSoft ループエンジニアリング用に初期化する。CLAUDE.md、tasks/、samples/、api/、scripts/、.claude/settings.json をテンプレートから配置する。既存の Mule プロジェクトにも新規にも使える。
argument-hint: "[--layer system|process|experience] [--name <api-name>]"
---

`${CLAUDE_PLUGIN_ROOT}/template/` の内容を今のリポジトリ直下に配置します。

## 手順
1. `git rev-parse --show-toplevel` でリポジトリ直下を確認する。git 管理外なら `git init` を提案してから進める。
2. 引数に `--layer` と `--name` が無ければ AskUserQuestion で聞く。
   - layer の選択肢: 「外部システム (SAP / DB / SaaS) を包む → system」「複数の system を組み合わせて業務の 1 手順にする → process」「画面や特定の利用者向けに形を整える → experience」。専門用語より用途の説明を前に出す。
3. template/ の各ファイルをコピーする。**既にあるファイルは上書きしない**。CLAUDE.md が既にある場合は末尾に template/CLAUDE.md の内容を追記し、冒頭にマーカー `<!-- mule-loop -->` を付ける。
4. CLAUDE.md の `layer:` と `name:` を埋める。
5. `mvn -v` と `dw --version` と `xmllint --version` の有無を確認し、無いものを表にして知らせる。無くても進められるが、検証が段 3 (mvn) だけになることを伝える。
6. 最後に「次は `/mule-start` で作りたい API を対話で決めます」とだけ案内する。
