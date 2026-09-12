#!/usr/bin/env python3
# Stop hook。mule-loop のリポジトリで 2 つ見る:
#   (1) 応答が 3 ブロックで締められているか
#   (2) **まだ進められるゴールがあるのに止まろうとしていないか** (scripts/goal-state.sh)
# stop_hook_active が true のときは通す (無限ループ防止)。
#
# (2) を入れた理由。「進められるゴールがあるか」は台帳と authorizations.yaml から機械が判定できる
# のに、**手順書が呼ぶ検査だったので呼び忘れても誰も気付きませんでした。** 止まる直前は hook が
# 効く唯一の場所なので、ここで見ます。exit 1 (進められる) のときだけ差し戻し、
# exit 2 (人の判断待ち) と exit 0 (完了) は通します — **待つのが正しい動作を邪魔しない**ため。
import json, os, pathlib, subprocess, sys

if not pathlib.Path("tasks").is_dir():
    sys.exit(0)

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    data = {}
if data.get("stop_hook_active") is True:
    sys.exit(0)

tp = data.get("transcript_path") or ""
if not tp or not os.path.isfile(tp):
    sys.exit(0)

last = ""
for line in open(tp, encoding="utf-8", errors="ignore"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "assistant":
        continue
    c = d.get("message", {}).get("content", [])
    t = "".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
    if t.strip():
        last = t
if not last:
    sys.exit(0)

# まだ進められるゴールがあるなら差し戻す。判定はスクリプトに任せる (状態を数え直さない)。
if os.path.isfile("scripts/goal-state.sh"):
    try:
        r = subprocess.run(["bash", "scripts/goal-state.sh"], capture_output=True, text=True, timeout=300)
        if r.returncode == 1:
            out = (r.stdout or "") + (r.stderr or "")
            print("[mule-loop] まだエージェント側で進められるゴールがあります。", file=sys.stderr)
            for l in out.splitlines():
                if "進められる:" in l:
                    print(l, file=sys.stderr)
            print("止まる理由を説明できないなら、/mule-run の手順で次のゴールを配ってください。", file=sys.stderr)
            print("人の判断が要るなら、どのゴールの何を判断してほしいのかを 1 つ書いてから止まってください。", file=sys.stderr)
            sys.exit(2)
    except Exception:
        pass

# AskUserQuestion 等で人に選ばせる番号付きの問いがある応答は通す
if "## 次にすること" not in last:
    print("[mule-loop] 応答を「## 現在地 / ## 次にすること / ## そのあと」の 3 ブロックで締めてください。"
          "次にすることは 1 つ。", file=sys.stderr)
    print("未完了ゴールがあり人の判断が要らないなら、止まらずに /mule-run の手順で次のゴールを"
          "配ってください。", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
