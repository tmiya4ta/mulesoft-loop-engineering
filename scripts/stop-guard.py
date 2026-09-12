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
import json, os, pathlib, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from casual_mode import casual          # noqa: E402

if not pathlib.Path("tasks").is_dir():
    sys.exit(0)
# カジュアルモードでは締め方を強制しない。台帳を使っていないので「まだ進められる」も言わない。
if casual() is not None:
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

# **書式は問わない。** 見出し (`## 次にすること`) でも太字 (`**次にすること**`) でも通す。
# ここで見たいのは「3 ブロックで締めたか」であって記法ではありません。`##` だけを認めていた版は、
# 太字で正しく締めた応答を差し戻し、**同じ報告が 2 回並びました** (実測: /mule-init 直後)。
# 人から見れば太字も見出しも同じ見た目なので、差し戻す値打ちがありません。
if not re.search(r"^[ \t]{0,3}(#{1,6}[ \t]*|\*\*|__)?[ \t]*次にすること", last, re.M):
    print("[mule-loop] 応答を「現在地 / 次にすること / そのあと」の 3 ブロックで締めてください。"
          "次にすることは 1 つ。見出し (`## 次にすること`) でも太字 (`**次にすること**`) でも構いません。",
          file=sys.stderr)
    # **既に 3 ブロックのつもりで書いているなら、書き直させない。** 全文を書き直すと同じ報告が
    # 2 回並びます。直すのは締めの部分だけ。
    print("既に 3 ブロックで書いているつもりなら、**全文を書き直さず締めの部分だけ**直してください。",
          file=sys.stderr)
    # ゴールが 1 件も無いときに「次のゴールを配れ」と言わない (/mule-init 直後がこれ)。
    if list(pathlib.Path("tasks").glob("T-*.md")):
        print("未完了ゴールがあり人の判断が要らないなら、止まらずに /mule-run の手順で次のゴールを"
              "配ってください。", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
