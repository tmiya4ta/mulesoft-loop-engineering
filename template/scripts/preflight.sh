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

# **git であることを最初に確かめる。** このループの仕掛けの多くは git が無いと
# エラーも警告も出さずに no-op になる。根拠はコードそのもの: wave-guard.sh は git の外では
# 設計として exit 0 で素通りし (worktree を誤爆しないため)、worktree 隔離は作れず、
# 「K ファイルが diff にあるか」は diff が取れず、--share は PR を出せない。
# **黙って効かない検査は、無い検査より悪い** (効いていると思って進むため)。
# deploy-guard は deny、coverage-check は exit 1 を返す。ここも同じく止める側に揃える。
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  {
    echo "preflight: ここは git リポジトリではない。この波は 1 件も配らない。"
    echo "git が無いと、次の 4 つが**エラーも出さずに何もしなくなる**:"
    echo "  - 実行エージェントの worktree 隔離 (並列ゴールが同じ木を踏み合う)"
    echo "  - wave-guard.sh の追記型ファイルの分担 (git が無いと素通りする設計)"
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

# **プロジェクトの scripts/ がプラグインより古くないか。** `/mule-init` は template/ を丸ごと
# コピーするので新規プロジェクトは揃うが、**プラグインを更新した既存プロジェクトは置いて行かれる**。
# 検査が 1 本欠けていても、その検査を呼ぶ手順が落ちるまで誰も気付かない。実際、今日 2 つの
# プロジェクトで 2 本が古いままだった (v0.6.29 で照合して気付いた)。
# **波は止めません。** 1 行の cp で直る話で、止めると全作業が塞がるためです。代わりに
# **直すコマンドをそのまま出します**。止める必要があるものは、その検査自身が止めます。
if [ -f scripts/plugin-root.sh ]; then
  tsrc=$(bash scripts/plugin-root.sh template/scripts 2>/dev/null || true)
  if [ -n "${tsrc:-}" ] && [ -d "$tsrc" ]; then
    stale=""
    for f in "$tsrc"/*.sh; do
      b=$(basename "$f")
      if [ ! -f "scripts/$b" ]; then stale="$stale $b(無し)"
      elif ! cmp -s "$f" "scripts/$b"; then stale="$stale $b(古い)"; fi
    done
    if [ -n "$stale" ]; then
      echo "preflight: scripts/ がプラグインより古いものがあります:$stale" >&2
      echo "           直す: cp $tsrc/*.sh scripts/ && chmod +x scripts/*.sh" >&2
      echo "           (波は止めません。検査が欠けたままだと、その検査が受け持つ失敗を取り逃します)" >&2
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
