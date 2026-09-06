#!/usr/bin/env bash
# 予算を確認する。/mule-run が 1 件配る前に必ず実行する。
# exit 0 = 配ってよい / exit 1 = 予算超過、止まれ
# 出力: remaining_runs=<n> remaining_min=<n> max_parallel=<n>
# remaining_min は「実行エージェントが動いていた時間」で数える (done の seconds の合計 + 動作中の dispatch の経過)。
# 人がゲートで止めている時間は数えない。壁時計で数えると、ゲートで人を待った時点で予算超過になってしまう。
set -u
B="${1:-budget.yaml}"; LOG="${2:-knowledge/run-log.jsonl}"
val() { sed -n "s/^ *$1: *\([0-9]*\).*/\1/p" "$B" | head -1; }
MAXR=$(val max_agent_runs); MAXM=$(val max_wall_clock_min); MAXP=$(val max)
: "${MAXR:=20}" "${MAXM:=90}" "${MAXP:=3}"
[ -f "$LOG" ] || { echo "remaining_runs=$MAXR remaining_min=$MAXM max_parallel=$MAXP"; exit 0; }
python3 - "$LOG" "$MAXR" "$MAXM" "$MAXP" <<'PY'
import json,sys,datetime
log,maxr,maxm,maxp=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4])
runs=0; active=0.0; open_={}
now=datetime.datetime.now(datetime.timezone.utc)
def ts(s):
    try: return datetime.datetime.fromisoformat(s.replace("Z","+00:00"))
    except Exception: return None
for line in open(log):
    try: d=json.loads(line)
    except: continue
    ev=d.get("event"); task=d.get("task")
    if ev=="dispatch":
        runs+=1
        t=ts(d.get("ts","")); 
        if t: open_.setdefault(task,[]).append(t)
    elif ev=="done":
        active+=float(d.get("seconds") or 0)
        if open_.get(task): open_[task].pop(0)
# done がまだ無い dispatch は今も動いているとみなして経過を足す
for lst in open_.values():
    for t in lst: active+=(now-t).total_seconds()
mins=int(active//60)
rr=maxr-runs; rm=maxm-mins
par=maxp if rr>maxr*0.25 else 1
print(f"remaining_runs={rr} remaining_min={rm} max_parallel={par}")
if rr<=0 or rm<=0:
    print(f"BUDGET EXCEEDED: runs {runs}/{maxr}, elapsed {mins}/{maxm}min",file=sys.stderr)
    sys.exit(1)
PY
