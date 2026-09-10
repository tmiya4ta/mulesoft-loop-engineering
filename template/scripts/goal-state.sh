#!/usr/bin/env bash
# 台帳の状態を 1 行にまとめ、**「エージェント側でこれ以上進められるか」を exit で答える。**
#
# なぜ必要か。`/goal` に「ぜんぶ pass」のような条件を置くと、残りのゴールが**人の許可待ちで
# 正当に止まっている**ときも「まだ終わっていない」と読まれ、同じ報告を繰り返しても再発火し続けた
# 実例がある (failures.jsonl、inventory2-api)。原因は **`blocked` が 2 つの意味を兼ねていて**、
# しかもそれが機械可読でなかったこと:
#   (1) `attempts` が 3 に達して諦めた (`/mule-run` 手順 5)
#   (2) `authorizations.yaml` が denied で段に入れない (`/mule-run` の deploy / policy)
# どちらも「人が動かないと 1 歩も進まない」で、**エージェントの努力では変わりません。**
# それを台帳から機械が判定して exit で返します。
#
# exit の意味:
#   0 = 全ゴールが passed (本当に完了)
#   1 = **進められるゴールがある** (エージェントはまだ働ける)
#   2 = **進められるゴールが 1 つも無いが未完了** (= 人の判断待ち。ここで止まるのが正しい)
#
# 「進められる」の定義: `status` が `todo`、または `failed` かつ `attempts < 3`。
# かつ `blocked_by` の全てが `passed`。かつ段の許可がある
# (`stage: deploy` なら `deploy.sandbox: allowed`、`stage: policy` なら `policy.sandbox: allowed`)。
#
# `/goal` の条件は「ぜんぶ pass」ではなく **「goal-state.sh が exit 0 か exit 2 になっている」**
# と書いてください。exit 2 は失敗ではなく「エージェント側は打ち止め」という状態です。
set -u

python3 - <<'PY'
import pathlib, re, sys

tasks = sorted(pathlib.Path("tasks").glob("T-*.md")) if pathlib.Path("tasks").is_dir() else []
if not tasks:
    print("goal-state: tasks/T-*.md がありません (/mule-start が未実行)", file=sys.stderr)
    sys.exit(2)

def front(p):
    t = p.read_text(errors="ignore")
    m = re.match(r'^---\n(.*?)\n---', t, re.S)
    d = {}
    for line in (m.group(1).splitlines() if m else []):
        mm = re.match(r'^([a-z_]+):\s*(.*)$', line)
        if mm:
            d[mm.group(1)] = mm.group(2).split("#", 1)[0].strip().strip('"')
    return d

# 許可はファイルが唯一の正。無ければ denied 扱い (書いていないものは全部禁止)。
auth = {}
ap = pathlib.Path("context/deployment/authorizations.yaml")
if ap.is_file():
    block = None
    for line in ap.read_text(errors="ignore").splitlines():
        line = line.split("#", 1)[0].rstrip()
        m = re.match(r'^([a-z_]+):\s*$', line)
        if m:
            block = m.group(1); continue
        m = re.match(r'^\s+([a-z_]+):\s*(\S+)', line)
        if m and block:
            auth[f"{block}.{m.group(1)}"] = m.group(2)

goals = {}
for p in tasks:
    d = front(p)
    gid = d.get("id") or p.stem
    goals[gid] = {
        "stage": d.get("stage") or "impl",
        "status": d.get("status") or "todo",
        "attempts": int(d.get("attempts") or 0),
        "deps": [x.strip() for x in (d.get("blocked_by") or "[]").strip("[]").split(",") if x.strip()],
        "file": str(p),
    }

counts = {}
for g in goals.values():
    counts[g["status"]] = counts.get(g["status"], 0) + 1

advanceable, held = [], []
for gid, g in sorted(goals.items()):
    if g["status"] in ("passed", "running"):
        continue
    reasons = []
    if g["status"] == "blocked":
        reasons.append("status: blocked (人が動かすまで進まない)")
    elif g["status"] == "failed" and g["attempts"] >= 3:
        reasons.append(f"attempts {g['attempts']} 回で打ち止め")
    unmet = [d for d in g["deps"] if goals.get(d, {}).get("status") != "passed"]
    if unmet:
        # 依存が「進められる」なら、それが動けばこちらも動く → 待ちであって打ち止めではない
        reasons.append(f"blocked_by が未完了: {', '.join(unmet)}")
    need = {"deploy": "deploy.sandbox", "policy": "policy.sandbox"}.get(g["stage"])
    if need and auth.get(need) != "allowed":
        reasons.append(f"authorizations.yaml の {need} が {auth.get(need, '未記入')} (人が書く)")
    if reasons:
        held.append((gid, g, reasons))
    else:
        advanceable.append(gid)

# 依存待ちだけのゴールは、依存側が進められるなら「波が進めば解ける」ので打ち止めに数えない
adv = set(advanceable)
progress_possible = bool(adv)

line = " ".join(f"{k}={v}" for k, v in sorted(counts.items()))
print(f"goal-state: {line} / 全 {len(goals)} 件 / 進められる {len(advanceable)} 件")
if advanceable:
    print(f"  進められる: {', '.join(advanceable)}")
for gid, g, reasons in held:
    print(f"  止まっている: {gid} (stage: {g['stage']}, status: {g['status']}) — {' / '.join(reasons)}")

if counts.get("passed", 0) == len(goals):
    print("goal-state: 全ゴール passed (完了)")
    sys.exit(0)
if progress_possible:
    print("goal-state: 進められるゴールがあります (エージェント側で続けられる)")
    sys.exit(1)
print("goal-state: **進められるゴールが 1 つも無く、未完了です。人の判断待ちです。**")
print("  エージェント側でできることはありません。上の「止まっている」の理由を人に伝えて止まります。")
print("  **authorizations.yaml を書き換えたり、許可の無い操作で回避してはいけません。**")
sys.exit(2)
PY
