#!/usr/bin/env bash
# 予算を確認する。/mule-run が 1 件配る前に必ず実行する。
# exit 0 = 配ってよい / exit 1 = 予算超過、止まれ
# 出力: remaining_runs=<n> remaining_min=<n> max_parallel=<n>
set -u
B="${1:-budget.yaml}"; LOG="${2:-knowledge/run-log.jsonl}"
val() { sed -n "s/^ *$1: *\([0-9]*\).*/\1/p" "$B" | head -1; }
MAXR=$(val max_agent_runs); MAXM=$(val max_wall_clock_min); MAXP=$(val max)
: "${MAXR:=20}" "${MAXM:=90}" "${MAXP:=3}"
[ -f "$LOG" ] || { echo "remaining_runs=$MAXR remaining_min=$MAXM max_parallel=$MAXP"; exit 0; }
python3 - "$LOG" "$MAXR" "$MAXM" "$MAXP" <<'PY'
import json,sys,datetime
log,maxr,maxm,maxp=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4])
runs=0; first=None
for line in open(log):
    try: d=json.loads(line)
    except: continue
    if d.get("event")!="dispatch": continue
    runs+=1
    t=d.get("ts")
    if t and (first is None or t<first): first=t
mins=0
if first:
    try:
        f=datetime.datetime.fromisoformat(first.replace("Z","+00:00"))
        mins=int((datetime.datetime.now(datetime.timezone.utc)-f).total_seconds()//60)
    except Exception: pass
rr=maxr-runs; rm=maxm-mins
par=maxp if rr>maxr*0.25 else 1
print(f"remaining_runs={rr} remaining_min={rm} max_parallel={par}")
if rr<=0 or rm<=0:
    print(f"BUDGET EXCEEDED: runs {runs}/{maxr}, elapsed {mins}/{maxm}min",file=sys.stderr)
    sys.exit(1)
PY
