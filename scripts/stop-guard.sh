#!/usr/bin/env bash
# Stop hook。mule-loop のリポジトリで 2 つ見る:
#   (1) 応答が 3 ブロックで締められているか
#   (2) **まだ進められるゴールがあるのに止まろうとしていないか** (scripts/goal-state.sh)
# stop_hook_active が true のときは通す (無限ループ防止)。
#
# (2) を入れた理由。「進められるゴールがあるか」は台帳と authorizations.yaml から機械が判定できる
# のに、**手順書が呼ぶ検査だったので呼び忘れても誰も気付きませんでした。** 止まる直前は hook が
# 効く唯一の場所なので、ここで見ます。exit 1 (進められる) のときだけ差し戻し、
# exit 2 (人の判断待ち) と exit 0 (完了) は通します — **待つのが正しい動作を邪魔しない**ため。
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

# まだ進められるゴールがあるなら差し戻す。判定はスクリプトに任せる (状態を数え直さない)。
if [ -f scripts/goal-state.sh ]; then
  gs=$(bash scripts/goal-state.sh 2>&1); grc=$?
  if [ "$grc" -eq 1 ]; then
    {
      echo "[mule-loop] まだエージェント側で進められるゴールがあります。"
      printf '%s\n' "$gs" | grep '進められる:' || true
      echo "止まる理由を説明できないなら、/mule-run の手順で次のゴールを配ってください。"
      echo "人の判断が要るなら、どのゴールの何を判断してほしいのかを 1 つ書いてから止まってください。"
    } >&2
    exit 2
  fi
fi

# AskUserQuestion 等で人に選ばせる番号付きの問いがある応答は通す
if ! printf '%s' "$last" | grep -q '## 次にすること'; then
  cat >&2 <<'EOT'
[mule-loop] 応答を「## 現在地 / ## 次にすること / ## そのあと」の 3 ブロックで締めてください。次にすることは 1 つ。
未完了ゴールがあり人の判断が要らないなら、止まらずに /mule-run の手順で次のゴールを配ってください。
EOT
  exit 2
fi
exit 0
