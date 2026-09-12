#!/usr/bin/env bash
# 波を配る前に、全ゴールが共有する土台を 1 回だけ確かめる。
# 目的は「N 体が同じ原因で各 3 回試して全滅する」のを防ぐこと。コスト 1 回で N×3 を止める。
#
# 見るのは、どのゴールにも共通する前提だけ:
#   依存の解決 (Exchange の 401、推測した GAV、手書き pom)、Java、アプリが固まること。
#
# **MUnit は流さない。** 実行ループの途中では失敗したゴールの red なテストが木に残っており、
# mvn test は設計どおり赤くなる。それで波を止めると、毎回 1 件目のゴール失敗で全部止まる。
# 使うコマンドは mule-init 手順 5b と同じもの (実績のある「このプロジェクトはビルドできるか」の検査)。
#
# exit 0 = 土台は健全。exit 2 = 落ちた (1 件も配らない)。
set -u

[ -f pom.xml ] || { echo "preflight: pom.xml が無い (/mule-init が済んでいない)" >&2; exit 2; }

# **このプラグインのスクリプトが前提にしているコマンド。** 無いと、スクリプトごとに違う場所で
# 違う顔をして落ちます (jq が無いと空文字が流れて「見つからない」と嘘をつく形になる)。
# ここで 1 回、名前を挙げて言います。**Windows は Git for Windows の bash が前提**で、
# jq と python3 は別に入れる必要があります (Git Bash には入っていません)。
missing=""
for c in python3 jq curl git; do command -v "$c" >/dev/null 2>&1 || missing="$missing $c"; done
if [ -n "$missing" ]; then
  {
    echo "preflight: 前提のコマンドが無い:$missing"
    echo "  入れ方 (例): macOS  brew install jq python3"
    echo "               Windows  winget install jqlang.jq / Python.Python.3.12  (bash は Git for Windows)"
    echo "               Linux    apt install jq python3 curl"
  } >&2
  exit 2
fi

# **git であることを最初に確かめる。** このループの仕掛けの多くは git が無いと
# エラーも警告も出さずに no-op になる。根拠はコードそのもの: wave-guard.py は git の外では
# 設計として exit 0 で素通りし (worktree を誤爆しないため)、worktree 隔離は作れず、
# 「K ファイルが diff にあるか」は diff が取れず、--share は PR を出せない。
# **黙って効かない検査は、無い検査より悪い** (効いていると思って進むため)。
# deploy-guard は deny、coverage-check は exit 1 を返す。ここも同じく止める側に揃える。
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  {
    echo "preflight: ここは git リポジトリではない。この波は 1 件も配らない。"
    echo "git が無いと、次の 4 つが**エラーも出さずに何もしなくなる**:"
    echo "  - 実行エージェントの worktree 隔離 (並列ゴールが同じ木を踏み合う)"
    echo "  - wave-guard.py の追記型ファイルの分担 (git が無いと素通りする設計)"
    echo "  - 「K ファイルが diff に含まれているか」の確認 (diff が取れない)"
    echo "  - /mule-learn --share の PR (昇格が共有されない)"
    echo "直し方: git init && git add -A && git commit -m 'initial'"
  } >&2
  exit 2
fi

# **リポジトリ直下の api/*.raml がクラスパスに乗っているか。** 直下のディレクトリは既定で乗らない。
# **これは下の mvn package では捕まりません** — package は成功し、落ちるのはアプリの初期化時
# (`InitialisationException: Raml not found at: api/<name>.raml`) です。実測 (台帳 T-001) では
# package が通ったあとにゴールを 1 件失いました。だから package の前に見ます。
# src/main/resources/api/ に置く構成は既定で乗るので、そのときはこの検査をしません。
if ls api/*.raml >/dev/null 2>&1 && ! ls src/main/resources/api/*.raml >/dev/null 2>&1 \
   && ! grep -qE "<directory>[[:space:]]*api[[:space:]]*</directory>" pom.xml; then
  {
    echo "preflight: 直下の api/*.raml がクラスパスに乗っていない。この波は 1 件も配らない。"
    echo "リポジトリ直下のディレクトリは既定でクラスパスに乗らないので、apikit:config の"
    echo "api=\"api/<name>.raml\" がアプリの初期化時に InitialisationException で落ちます"
    echo "(mvn package は通るので、ここで見ないと配ったあとに気付きます)。"
    echo "直し方: pom.xml の <build><resources> に足す —"
    echo "  <resource><directory>api</directory><targetPath>api</targetPath></resource>"
  } >&2
  exit 2
fi

# **プロジェクトの scripts/ がプラグインと一致しているか。** `/mule-init` は template/ を丸ごと
# コピーするので新規プロジェクトは揃うが、**プラグインを更新した既存プロジェクトは置いて行かれる**。
# 検査が 1 本欠けていても、その検査を呼ぶ手順が落ちるまで誰も気付かない。実際、今日 2 つの
# プロジェクトで 2 本が古いままだった (v0.6.29 で照合して気付いた)。
# **波は止めません。** 1 行の cp で直る話で、止めると全作業が塞がるためです。代わりに
# **直すコマンドをそのまま出します**。止める必要があるものは、その検査自身が止めます。
if [ -f scripts/plugin-root.sh ]; then
  tsrc=$(bash scripts/plugin-root.sh template/scripts 2>/dev/null || true)
  if [ -n "${tsrc:-}" ] && [ -d "$tsrc" ]; then
    stale=""
    # **.sh と .py の両方を見る。** v0.6.44 から一部の道具は Python (拡張子が変わったのに
    # .sh だけ照合していると、新しい .py が配られていないことに気付けない)。
    for f in "$tsrc"/*.sh "$tsrc"/*.py; do
      [ -f "$f" ] || continue
      b=$(basename "$f")
      if [ ! -f "scripts/$b" ]; then stale="$stale $b(無し)"
      # **「古い」と断定しない。** どちらが新しいかはこのスクリプトには分かりません
      # (プラグインより新しいものを手で置いている場合もある。実測でそうなった)。
      elif ! cmp -s "$f" "scripts/$b"; then stale="$stale $b(差分あり)"; fi
    done
    if [ -n "$stale" ]; then
      echo "preflight: scripts/ がプラグインと違うものがあります:$stale" >&2
      echo "           直す: cp $tsrc/*.sh $tsrc/*.py scripts/ && chmod +x scripts/*.sh scripts/*.py" >&2
      echo "           (波は止めません。検査が欠けたままだと、その検査が受け持つ失敗を取り逃します)" >&2
    fi
  fi
fi

# **hook は cache から読まれ、セッション開始時に固定される。** プラグインを更新しても、
# **走っているセッションの hook は古いまま**です。波は wave-guard / secret-guard / deploy-guard に
# 頼っているので、ここで言います。実測 (2026-09-10): cache の最新が 0.6.29 のとき
# plugin-root.sh が返す実体は 0.6.30 で、v0.6.30 の hook は効いていませんでした。
# **どの cache をハーネスが選んだかはシェルからは読めない** (CLAUDE_PLUGIN_ROOT は env に無い。
# v0.6.10 で実測) ので、断定せず「古い可能性がある」と言います。波は止めません。
if [ -f scripts/plugin-root.sh ]; then
  real=$(bash scripts/plugin-root.sh 2>/dev/null || true)
  if [ -n "${real:-}" ]; then
    vreal=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$real/.claude-plugin/plugin.json" 2>/dev/null | head -1)
    vcache=$(ls -d "$HOME"/.claude/plugins/cache/*/mule-loop/*/ 2>/dev/null | sort -V -r | head -1)
    [ -n "${vcache:-}" ] && vcache=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$vcache/.claude-plugin/plugin.json" 2>/dev/null | head -1)
    if [ -n "${vreal:-}" ] && [ -n "${vcache:-}" ] && [ "$vreal" != "$vcache" ]; then
      echo "preflight: hook が古い可能性があります (cache の最新 $vcache / 実体 $vreal)。" >&2
      echo "           hook (wave-guard, secret-guard, deploy-guard, stop-guard) は cache から読まれ、" >&2
      echo "           セッション開始時に固定されます。**実体側で直した hook は次のセッションから効きます。**" >&2
      echo "           この波でその hook に頼るなら、セッションを開き直してください。" >&2
    fi
  fi
fi

cmd="mvn -q clean package -DskipTests"
out=$($cmd 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  {
    echo "preflight: \`$cmd\` が exit $rc で落ちた。土台が壊れているので この波は 1 件も配らない。"
    echo "--- 出力 (原文、末尾 40 行) ---"
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi
echo "preflight: ok ($cmd)"

# スキーマ索引を pom.xml より古ければ作り直す。~/.m2 は上の package で埋まっている。
# **ここの失敗で波を止めない。** 土台の判定はあくまで上の package の結果で、
# 索引はあると速くなる補助にすぎない (無ければエージェントは gotchas → スキルの順に戻るだけ)。
idx=reference/mule-schema/INDEX.md
if [ -f scripts/schema-index.sh ] && { [ ! -f "$idx" ] || [ pom.xml -nt "$idx" ]; }; then
  bash scripts/schema-index.sh || echo "preflight: schema-index は失敗した (波は止めない)" >&2
fi

# 索引が .gitignore で除外されていないか。除外されていると /mule-run の `git add -A` に入らず、
# worktree (origin/main から切られる) の実行エージェントに届かない。**届かないことは黙って起きる**
# ので、ここで言う。**波は止めない** (索引が無くても gotchas → スキルの順に戻れるだけなので)。
if [ -f "$idx" ] && git check-ignore -q "$idx" 2>/dev/null; then
  echo "preflight: $idx が .gitignore で除外されている。worktree の実行エージェントには届かないので" >&2
  echo "           コネクタの要素名を推測することになる。除外を外してコミットの対象にしてください。" >&2
fi
