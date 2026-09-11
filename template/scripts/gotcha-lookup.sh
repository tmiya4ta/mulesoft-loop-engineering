#!/usr/bin/env bash
# エラーの原文 (や症状の言葉) から、**既に分かっていること**を引く。
#
# なぜ必要か。知識は書いてあるのに、**必要な瞬間に見つけられない**ことが一番の損でした。
# 実例 (inventory3-api、2026-09-11): Flex Gateway の制約は knowledge/gotchas/api-manager.md に
# ほぼ全部書いてあったのに、読まずに Web 検索と API の試行錯誤で同じ結論に何度も辿り着いた。
# 索引を読んで主題を選ぶ、は**エラーを見ている最中の人にはできない**。原文をそのまま渡せば
# 当たる項目を丸ごと出す、という道具にします。
#
# 使い方:
#   bash scripts/gotcha-lookup.sh 'Cannot coerce Object to String'
#   bash scripts/gotcha-lookup.sh 'ORA-12505'
#   bash scripts/gotcha-lookup.sh 'Stream Compatible'
# **エラーの原文の、固有名詞や数字を除いた特徴的な部分**を渡すのが一番当たります。
#
# 探す順 (近いものから):
#   1. このプロジェクトの knowledge/K-*.md と context/environment/  (この接続先の事実)
#   2. プラグインの knowledge/gotchas/*.md                            (実測した地雷。項目を丸ごと出す)
#   3. プラグインの knowledge/basics/*.md                             (1 行 1 事実。行を出す)
#
# exit 0 = 当たった (出力に従う) / exit 1 = どこにも無い (下の「次にすること」を出す)
set -u
q=${1:?使い方: gotcha-lookup.sh '<エラーの原文の一部>'}
root=$(bash "$(dirname "$0")/plugin-root.sh" 2>/dev/null || true)

python3 - "$q" "${root:-}" <<'PY'
import pathlib, re, sys
q, root = sys.argv[1], sys.argv[2]
ql = q.lower()
hits = 0

def show(title, path, body):
    global hits
    hits += 1
    print(f"━━ {title}  ({path})")
    print(body.rstrip())
    print()

# 1. このプロジェクト
for p in sorted(pathlib.Path("knowledge").glob("K-*.md")) + sorted(pathlib.Path("context/environment").glob("*.md")):
    t = p.read_text(errors="ignore")
    if ql in t.lower():
        # 当たった行の前後だけ出す (K ファイルは長いことがある)
        lines = t.splitlines()
        for i, l in enumerate(lines):
            if ql in l.lower():
                a, b = max(0, i - 3), min(len(lines), i + 6)
                show("このプロジェクトの記録", p, "\n".join(lines[a:b]))
                break

# 2. プラグインの gotchas: ## 項目を丸ごと
if root:
    for p in sorted(pathlib.Path(root, "knowledge/gotchas").glob("*.md")):
        t = p.read_text(errors="ignore")
        parts = re.split(r'(?m)^(?=## )', t)
        for part in parts:
            if part.startswith("## ") and ql in part.lower():
                title = part.splitlines()[0][3:]
                body = re.sub(r'\n---\s*$', '', part.strip())
                show(f"既知の地雷: {title}", f"knowledge/gotchas/{p.name}", body)
    # 3. basics: 行
    for p in sorted(pathlib.Path(root, "knowledge/basics").glob("*.md")):
        for l in p.read_text(errors="ignore").splitlines():
            if l.startswith("- ") and ql in l.lower():
                show("基礎知識", f"knowledge/basics/{p.name}", l)

if hits:
    print(f"gotcha-lookup: {hits} 件当たりました。**上に書いてある直し方に従ってください。**")
    print("  自分で調べ直す前に、上の「根拠」が今の状況と同じか (同じ DB 製品か、同じコネクタか) だけ確かめる。")
    sys.exit(0)

print(f"gotcha-lookup: '{q}' はどこにも書いてありません。")
print("次にすること (この順で。上から順に試して、当たったらそこで止まる):")
print("  1. もっと短い言葉で引き直す (エラー型だけ、例: 'MULE:EXPRESSION'、'ORA-00942'、'HTTP:CONNECTIVITY')")
print("  2. コネクタの要素名・操作名の話なら reference/mule-schema/INDEX.md を開く")
print("  3. bash scripts/plugin-root.sh --skill platform-assistant (Anypoint 側の操作なら)")
print("  4. 公式マニュアル")
print("  **やってはいけない**: このリポジトリの外 (隣のプロジェクト) を読む / 推測で書いて試す")
print("  分かったら bash scripts/k-new.sh <ゴール id> が出したパスに書く。次の人が 1 で引けるように。")
sys.exit(1)
PY
