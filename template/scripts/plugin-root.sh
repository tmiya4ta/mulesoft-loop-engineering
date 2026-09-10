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
set -u

# 候補を新しい版から並べる。knowledge/mule-basics.md の有無で「これは mule-loop の実体か」を判定する。
candidates() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then
    printf '%s\n' "${CLAUDE_PLUGIN_ROOT}"
  fi
  ls -d "$HOME"/.claude/plugins/cache/*/mule-loop/*/ 2>/dev/null | sort -V -r
  ls -d "$HOME"/.claude/plugins/marketplaces/*/ 2>/dev/null
}

root=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  d=${d%/}
  [ -f "$d/knowledge/mule-basics.md" ] && { root=$d; break; }
done < <(candidates)

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
