#!/usr/bin/env bash
# 4 指標を出す。元データは knowledge/run-log.jsonl と tasks/*.md。
set -u
python3 - <<'PY'
import json,glob,re,os,collections,statistics
log="knowledge/run-log.jsonl"
disp={}; secs=[]; rev=collections.Counter(); models=collections.Counter()
if os.path.exists(log):
    for line in open(log):
        try: d=json.loads(line)
        except: continue
        e=d.get("event")
        if e=="dispatch": disp[d.get("task")]=d.get("ts"); models[d.get("model")]+=1
        elif e=="done" and d.get("seconds"): secs.append(float(d["seconds"]))
        elif e=="review": rev[d.get("verdict")]+=1
tot=first=0; passed=0
for f in sorted(glob.glob("tasks/T-*.md")):
    s=open(f).read()
    st=re.search(r'^status:\s*(\S+)',s,re.M); at=re.search(r'^attempts:\s*(\d+)',s,re.M)
    if not st: continue
    tot+=1
    if st.group(1)=="passed":
        passed+=1
        if at and int(at.group(1))<=1: first+=1
print("| 指標 | 値 |")
print("|---|---|")
print(f"| ループ 1 周の時間 (中央値) | {statistics.median(secs):.0f} 秒 |" if secs else "| ループ 1 周の時間 (中央値) | データなし |")
print(f"| 初回で done_when を通った率 | {first}/{passed} ({100*first//passed if passed else 0}%) |")
print(f"| レビュー差し戻し | {rev.get('request-changes',0)} 回 (approve {rev.get('approve',0)}) |")
cov=os.popen("bash scripts/coverage-check.sh 2>/dev/null | head -1").read().strip()
print(f"| flow カバレッジ | {cov or '未計測'} |")
print(f"| 実行エージェント起動 | {sum(models.values())} 回 {dict(models)} |")
print(f"| ゴール | 全 {tot} / passed {passed} |")
PY
