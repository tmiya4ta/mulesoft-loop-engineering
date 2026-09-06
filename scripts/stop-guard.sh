#!/usr/bin/env bash
# Stop hook。mule-loop のリポジトリで、応答が 3 ブロックで締められていなければ 1 回だけ差し戻す。
# stop_hook_active が true のときは通す (無限ループ防止)。
[ -d tasks ] || exit 0
input=$(cat)
printf '%s' "$input" | grep -q '"stop_hook_active": *true' && exit 0
tp=$(printf '%s' "$input" | sed -n 's/.*"transcript_path": *"\([^"]*\)".*/\1/p')
[ -f "$tp" ] || exit 0
last=$(python3 - "$tp" <<'PY'
import json,sys
txt=""
for line in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    try: d=json.loads(line)
    except Exception: continue
    if d.get("type")!="assistant": continue
    c=d.get("message",{}).get("content",[])
    t="".join(x.get("text","") for x in c if isinstance(x,dict) and x.get("type")=="text")
    if t.strip(): txt=t
print(txt)
PY
)
[ -z "$last" ] && exit 0
# AskUserQuestion 等で人に選ばせる番号付きの問いがある応答は通す
if ! printf '%s' "$last" | grep -q '## 次にすること'; then
  cat >&2 <<'EOT'
[mule-loop] 応答を「## 現在地 / ## 次にすること / ## そのあと」の 3 ブロックで締めてください。次にすることは 1 つ。
未完了ゴールがあり人の判断が要らないなら、止まらずに /mule-run の手順で次のゴールを配ってください。
EOT
  exit 2
fi
exit 0
