#!/usr/bin/env bash
# PreToolUse(Bash) hook。Sandbox へのデプロイを「人が毎回押す承認」ではなくファイルで判定する。
#
# 判定者を人から機械に移すのがこのリポジトリの作り方なので、デプロイだけ人の Enter に
# 頼っているのは筋が通らない。許可はもともと context/deployment/authorizations.yaml に
# 書いてある。それを読んで allow / deny を返す。
#
#   deploy.sandbox が allowed でない            → deny (ファイルを直すのは人)
#   環境名が Production 系、または空で確認できない → deny (本番は常に人が手で行う)
#   両方満たす                                   → allow (プロンプト無しで通す)
#
# 環境名は sandbox.yaml と pom.xml の両方を見る。実際に mvn が使うのは pom なので、
# sandbox.yaml が Sandbox でも pom が Production を指していれば止める。
#
# ★探す起点は hook 入力の cwd で、そこから git ルートまで遡って authorizations.yaml を探す。
#   相対パスで開くと、monorepo や worktree で作業ディレクトリがプロジェクト直下でないとき
#   ファイルを見つけられず、無言で素通り (= 無防備なデプロイ) になる。v0.6.7 で実際に
#   踏んだ相対パス解決の事故と同じ形。コマンドが絶対パスへ `cd` してから走る形 (mule-run が
#   実行エージェントに配る形) なら、その `cd` 先を起点にする。
#   遡っても見つからなければ mule-loop のリポジトリではないので、何も言わずに通常の許可判定へ返す。
set -u
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# デプロイのコマンドでなければ介入しない (`mvn mule:deploy` / `deploy:deploy` の形も捕まえる)
DEPLOY='(mvn[^;|&]*([[:space:]:]deploy|-DmuleDeploy)|anypoint-cli(-v4)?[^;|&]*[[:space:]]deploy)'
printf '%s' "$cmd" | grep -qE "$DEPLOY" || exit 0

start=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
cdto=$(printf '%s' "$cmd" | sed -n 's/^[[:space:]]*cd[[:space:]]\{1,\}\([^;&|]*\).*/\1/p' | head -1 | tr -d "\"'" | sed 's/[[:space:]]*$//')
case "$cdto" in /*) [ -d "$cdto" ] && start=$cdto ;; esac
[ -n "$start" ] || start=$PWD

root=""; dir=$start
while [ -n "$dir" ]; do
  [ -f "$dir/context/deployment/authorizations.yaml" ] && { root=$dir; break; }
  [ -e "$dir/.git" ] && break        # git ルートまで来た = このリポジトリには無い
  parent=$(dirname "$dir"); [ "$parent" = "$dir" ] && break; dir=$parent
done
[ -n "$root" ] || exit 0             # mule-loop のリポジトリでなければ何も言わない
auth="$root/context/deployment/authorizations.yaml"

say() {  # say <allow|deny> <reason>
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# authorizations.yaml の deploy: ブロックから sandbox: の値だけ取る (policy: の同名キーと混ぜない)
allowed=$(awk '
  /^deploy:/ {f=1; next}
  /^[^[:space:]#]/ {f=0}
  f && /^[[:space:]]+sandbox:/ {sub(/#.*/,""); sub(/^[[:space:]]*sandbox:[[:space:]]*/,""); gsub(/[[:space:]"]/,""); print; exit}
' "$auth")

[ "$allowed" = allowed ] || say deny \
"$auth の deploy.sandbox が「${allowed:-未設定}」です。デプロイの許可はこのファイルにしか無く、書き換えるのは人です。
Sandbox に置いてよいなら deploy.sandbox: allowed にしてから、もう一度このコマンドを流してください。"

env_sb=""; [ -f "$root/context/deployment/sandbox.yaml" ] && \
  env_sb=$(sed -n 's/^environment:[[:space:]]*\([^#]*\).*/\1/p' "$root/context/deployment/sandbox.yaml" | head -1 | tr -d ' "')
env_pom=""; [ -f "$root/pom.xml" ] && \
  env_pom=$(sed -n 's:.*<environment>\([^<]*\)</environment>.*:\1:p' "$root/pom.xml" | head -1 | tr -d ' ')

# Production 系の名前。prd は Anypoint でよく使う略記なので prod と別に見る。
PROD='prod|(^|[^a-z])prd([^a-z]|$)|本番'
for e in "$env_sb" "$env_pom"; do
  printf '%s' "$e" | grep -qiE "$PROD" && say deny \
"デプロイ先の環境名が「$e」です。本番は常に人が Runtime Manager から手で行うので、このループは Production 系の環境には向けません。
Sandbox に置くつもりなら $root/context/deployment/sandbox.yaml の environment と pom.xml の <environment> を確かめてください。"
done

[ -n "$env_sb$env_pom" ] || say deny \
"デプロイ先の環境名が context/deployment/sandbox.yaml にも pom.xml にも無く、Sandbox かどうか確かめられません。
sandbox.yaml の environment を書いてから流してください (空のまま通すと本番に向く事故が止められません)。"

# 許可はある。最後に **jar に秘密が混入していないか**見る。
# `-DattachMuleSources` はプロジェクト全体を丸ごと jar に入れ `.gitignore` を見ないので、
# **publish したあとに気付いても取り返せない** (Exchange に上がった時点で組織の全員から見える)。
# 手順書は `mvn clean package` の直後に `jar-leak-check.sh` を呼ぶが、**呼び忘れても
# 気付けない**ので、jar が既にあるならここでも見る。無ければ何も言わない (これから作るので)。
if [ -f "$root/scripts/jar-leak-check.sh" ] && ls "$root"/target/*.jar >/dev/null 2>&1; then
  leak=$(cd "$root" && bash scripts/jar-leak-check.sh 2>&1); lrc=$?
  [ "$lrc" -eq 2 ] && say deny \
"target/ にある jar に **git が無視しているファイル** が入っています。publish すると Exchange に上がり、組織の全員から見えます。

$leak

秘密を持つファイルはプロジェクトの外 (例: ~/<app>-credential、パーミッション 600) に置き、jar を削除して作り直してください。
**.gitignore は jar には効きません** (-DattachMuleSources はファイルシステムを丸ごと入れる)。"
fi

say allow "deploy.sandbox: allowed / 環境「${env_pom:-$env_sb}」。$auth の許可で通しました。"
