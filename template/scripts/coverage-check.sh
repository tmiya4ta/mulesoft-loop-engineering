#!/usr/bin/env bash
# フローのカバレッジを構造的に確認する。EE ライセンスが無くても必ず動く。
# src/main/mule/*.xml の全 flow / sub-flow が、src/test/munit/*.xml のどれかから
# flow-ref されているかを見る。未カバーが 1 つでもあれば exit 1。
#
# 限界: これは「flow に到達しているか」だけを見る。flow の中の choice / try /
# error-handler の分岐までは見ない。分岐は samples のケースを増やして通すこと。
# 本物のカバレッジ率は EE 限定 (scripts/munit-coverage-mode.sh を参照)。
set -u
python3 - "${1:-src/main/mule}" "${2:-src/test/munit}" <<'PY'
import sys,os,re,glob
main,test=sys.argv[1],sys.argv[2]
if not os.path.isdir(main): print("no %s"%main,file=sys.stderr); sys.exit(0)
def read(d):
    s=""
    for p in glob.glob(os.path.join(d,"**","*.xml"),recursive=True): s+=open(p,errors="ignore").read()+"\n"
    return s
src, tst = read(main), read(test) if os.path.isdir(test) else ""
# 定義側: <flow name="..."> / <sub-flow name="...">  (doc:name は拾わない)
flows=[]
for m in re.finditer(r'<(?:sub-)?flow\b[^>]*?>', src, re.S):
    n=re.search(r'(?<![\w:])name\s*=\s*"([^"]+)"', m.group(0))
    if n: flows.append(n.group(1))
flows=sorted(set(flows))
# 参照側: <flow-ref ... name="..."> のみ。属性順は問わない。複数行にまたがってよい
refs=set()
for m in re.finditer(r'<flow-ref\b[^>]*?/?>', tst, re.S):
    n=re.search(r'(?<![\w:])name\s*=\s*"([^"]+)"', m.group(0))
    if n: refs.add(n.group(1))
if not flows: print("flow がありません"); sys.exit(0)
miss=[f for f in flows if f not in refs]
c=len(flows)-len(miss)
print("flow coverage: %d/%d (%d%%)"%(c,len(flows),c*100//len(flows)))
if miss:
    print("未カバーの flow: "+" ".join(miss),file=sys.stderr)
    print("→ 各 flow を flow-ref する munit:test を追加してください",file=sys.stderr)
    sys.exit(1)
PY
