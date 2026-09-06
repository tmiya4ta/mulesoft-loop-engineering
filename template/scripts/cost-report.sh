#!/usr/bin/env bash
# セッションの実コストを Claude Code のトランスクリプトから読む。
# 注意: サブエージェント (実行エージェント) の行には usage が載らないため、
#       行単位の合計では取れない。セッション要約行の modelUsage / totalCostUSD を使う。
#       これはセッション終了時に書かれるので、走行中の上限判定には budget-check.sh を使う。
set -u
slug=$(pwd | sed 's#/#-#g')
dir="$HOME/.claude/projects/$slug"
[ -d "$dir" ] || dir=$(ls -dt "$HOME"/.claude/projects/* 2>/dev/null | head -1)
python3 - "$dir" <<'PY'
import json,sys,glob,os
d=sys.argv[1]
rows=[]
for p in sorted(glob.glob(os.path.join(d,"*.jsonl")), key=os.path.getmtime, reverse=True):
    for line in open(p,errors='ignore'):
        if '"totalCostUSD"' not in line: continue
        try: j=json.loads(line)
        except: continue
        rows.append((os.path.basename(p)[:8], j.get("totalCostUSD"), j.get("modelUsage") or {}))
if not rows:
    print("コスト要約行がまだありません (セッション終了時に書かれます)。")
    print("走行中の予算は scripts/budget-check.sh を使ってください。"); raise SystemExit
print("| セッション | USD | モデル別 |"); print("|---|---|---|")
for s,c,mu in rows[:10]:
    per=", ".join(f"{k}: {v.get('costUSD',0):.3f}" for k,v in mu.items())
    print(f"| {s} | {c:.3f} | {per} |")
print(f"\n合計 {sum(r[1] or 0 for r in rows):.2f} USD ({len(rows)} セッション)")
PY
