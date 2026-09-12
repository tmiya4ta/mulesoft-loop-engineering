#!/usr/bin/env bash
# knowledge/ の索引と実体が一致しているかを検査する。**プラグインのリポジトリで走らせる**
# (索引はプラグイン側にあり、利用者のプロジェクトには配らないので template/scripts には置かない)。
#
# なぜ必要か。v0.6.15 で gotchas.md / mule-basics.md を索引 + 主題別ファイルに割ったとき、
# **索引の行数を全部 1 ずつ間違えた** (数字を書いた後に各ファイルの見出しを 1 行縮めたため)。
# しかも同じコミットで「索引が実体とずれると読む側はそのファイルを開かなくなる」と警告している。
# 手で持つ数字は、警告を書いた本人がその場でずらせる。だから機械が持つ。
#
# v0.6.16 で行数の列そのものを落とした。行数は編集のたびに動くのに、読む側がどの主題を開くかには
# 一切効かない。残したのは **件数** だけで、これは項目を足したときにだけ動く
# (= `/mule-learn` が索引を触るのと同じ瞬間)。
#
# 見るのは 4 つ:
#   1. 実体にあるファイルが索引に載っているか
#   2. 索引の行に対応する実体があるか
#   3. gotchas 索引の「件」が `## ` 見出しの数と一致しているか
#   4. 【未解決】の項目に、`portal-search.py` で公式 API の仕様を引いた記録があるか
#      — v0.6.37 で「Managed Flex Gateway の公開 URL は API から取れない」を【未解決】として取り込み、
#      「人に画面を見てもらう」を手順にした。実際は Gateway Manager API の応答にそのまま載っていた。
#      見ていたのは 36 本中 2 本の API だけだった。**探していないことを「取れない」と書いた項目は、
#      読んだ全員を人に聞く方へ誘導する。** だから引いた記録の無い【未解決】は通さない。
#
# 使い方: bash scripts/knowledge-index-check.sh   (exit 0 = 一致、exit 1 = ずれ)
# `/mule-learn --share` は PR を開く前にこれを通す。
set -u
cd "$(dirname "$0")/.." || exit 1

python3 - <<'PY'
import pathlib, re, sys

bad = []

def rows(idx, prefix):
    """索引から (slug, 件数 or None) を拾う。件数の列がある表だけ数字を返す。"""
    out = {}
    for line in pathlib.Path(idx).read_text().splitlines():
        if not line.startswith("|"):
            continue
        m = re.search(rf'`{prefix}/([a-z-]+)\.md`\s*\|\s*(\d+)?', line)
        if m:
            out[m.group(1)] = int(m.group(2)) if m.group(2) else None
    return out

for idx, d, prefix, counted in (("knowledge/gotchas.md", "knowledge/gotchas", "gotchas", True),
                                ("knowledge/mule-basics.md", "knowledge/basics", "basics", False)):
    listed = rows(idx, prefix)
    actual = {p.stem: p for p in pathlib.Path(d).glob("*.md")}

    for slug in sorted(set(actual) - set(listed)):
        bad.append(f"{d}/{slug}.md が {idx} の表に無い — 行を足す (読む側はこのファイルを開けない)")
    for slug in sorted(set(listed) - set(actual)):
        bad.append(f"{idx} が {d}/{slug}.md を指しているが実体が無い")

    if not counted:
        continue
    for slug in sorted(set(listed) & set(actual)):
        want = listed[slug]
        got = sum(1 for l in actual[slug].read_text().splitlines() if l.startswith("## "))
        if want is None:
            bad.append(f"{idx} の {prefix}/{slug}.md の行に件数が無い")
        elif want != got:
            bad.append(f"{idx} の {prefix}/{slug}.md は {want} 件だが実体は {got} 件 — 索引を直す")

for p in sorted(pathlib.Path("knowledge/gotchas").glob("*.md")):
    for part in re.split(r'(?m)^(?=## )', p.read_text()):
        title = part.splitlines()[0] if part.startswith("## ") else ""
        if "未解決" in title and "portal-search.py" not in part:
            bad.append(f"{p} の「{title[3:]}」は【未解決】なのに、portal-search.py で公式 API の仕様を"
                       f"引いた記録が無い — `python3 template/scripts/portal-search.py '<項目名>'` を引いて、"
                       f"引いた語と結果を本文に書く (外れたら anypoint-api.py --find で応答も探す)")

if bad:
    print("knowledge-index-check: 索引と実体がずれている", file=sys.stderr)
    for b in bad:
        print(f"  - {b}", file=sys.stderr)
    sys.exit(1)
print("knowledge-index-check: 索引と実体は一致 (gotchas 9 主題 / basics 10 主題)")
PY
