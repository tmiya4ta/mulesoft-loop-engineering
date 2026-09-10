#!/usr/bin/env bash
# プラグイン (mule-loop) の実体と、外部スキルの SKILL.md の場所をパスに解決する。
#
# なぜ必要か。エージェントのプロンプトに書いた `${CLAUDE_PLUGIN_ROOT}` はハーネスが読み込み時に
# 展開する (実測: skills の本文では `/home/.../plugins/cache/<marketplace>/mule-loop/<版>/` に
# 置き換わっていた)。ただし **シェルの環境変数には存在しない** (実測: `env` に無い)。
# だから `bash -c 'cat $CLAUDE_PLUGIN_ROOT/knowledge/gotchas.md'` は必ず空振りする。
# さらに展開先は **版つきのキャッシュ** なので、版が上がるとパスが変わる。絶対パスを
# ドキュメントや台帳に書き写すと、次の版で開けなくなる。
#
# 実行エージェントは Skill ツールを持たない (`tools:` に無い) ので、スキルを名前で呼べない。
# 名前ではなくパスに解決してから Read する必要がある。それを機械にやらせるのがこのスクリプト。
#
# 使い方:
#   bash scripts/plugin-root.sh                        → プラグインの実体 (最新版) の絶対パス
#   bash scripts/plugin-root.sh knowledge/gotchas.md   → その中のファイルの絶対パス
#   bash scripts/plugin-root.sh --skill secure-api     → そのスキルの SKILL.md の絶対パス
#
# 見つからなければ **何も出さず exit 1**。呼ぶ側は「無い」と分かったらそこで諦めて、
# gotchas → reference/mule-schema/INDEX.md → マニュアルの順に戻る。探し回らない。
#
# **候補の順ではなく plugin.json の版で選ぶ。** cache は**セッション開始時にだけ**作られるので、
# git push 済みでも走っているセッションの cache には現れない。実測 (2026-09-10、v0.6.15):
# marketplaces のクローンは 0.6.15 なのに cache の最新は 0.6.8 で、「候補の先頭から」選ぶ実装は
# **0.6.8 を返した**。その版に無いファイルを指定すると「プラグイン内に無い」と嘘を言う。
# 全候補の plugin.json を読んで版が最大のものを採る。ナレッジは版が上がっても足されるだけなので、
# 新しい方を渡して困ることはない。
set -u

# 候補。knowledge/mule-basics.md の有無で「これは mule-loop の実体か」を判定する。
candidates() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then
    printf '%s\n' "${CLAUDE_PLUGIN_ROOT}"
  fi
  ls -d "$HOME"/.claude/plugins/cache/*/mule-loop/*/ 2>/dev/null
  ls -d "$HOME"/.claude/plugins/marketplaces/*/ 2>/dev/null
}

# 「版<TAB>パス」を並べて sort -V の最後を採る。版が読めないものは 0.0.0 扱い (最後の手段として残す)。
root=$(
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    d=${d%/}
    [ -f "$d/knowledge/mule-basics.md" ] || continue
    v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$d/.claude-plugin/plugin.json" 2>/dev/null | head -1)
    printf '%s\t%s\n' "${v:-0.0.0}" "$d"
  done < <(candidates) | sort -V -k1,1 | tail -1 | cut -f2-
)

[ -n "$root" ] || { echo "plugin-root: mule-loop の実体が見つからない (プラグインが入っていない)" >&2; exit 1; }

case "${1:-}" in
  "")
    printf '%s\n' "$root"
    ;;
  --skill)
    name=${2:?--skill にはスキル名が必要}
    for p in "$root/skills/$name/SKILL.md" \
             "$HOME/.claude/skills/$name/SKILL.md" \
             "$HOME"/.claude/plugins/cache/*/*/*/skills/"$name"/SKILL.md \
             "$HOME"/.claude/plugins/marketplaces/*/skills/"$name"/SKILL.md; do
      [ -f "$p" ] && { printf '%s\n' "$p"; exit 0; }
    done
    echo "plugin-root: スキル '$name' は入っていない (/mule-setup が未実行か、導入に失敗している)" >&2
    exit 1
    ;;
  *)
    p="$root/$1"
    [ -e "$p" ] || { echo "plugin-root: $1 はプラグイン内に無い ($root)" >&2; exit 1; }
    printf '%s\n' "$p"
    ;;
esac
