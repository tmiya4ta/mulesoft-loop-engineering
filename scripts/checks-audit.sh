#!/usr/bin/env bash
# `docs/methodology.md` の「検査の並び (走る順)」の表が、**実体と合っているか**を検査する。
#
# なぜ必要か。表は v0.6.28 で「手順書に散っている検査を 1 本に並べる」ために書いたが、
# **書いた本人の主張のまま**で、実体と突き合わせていなかった。突き合わせたら 20 行のうち 1 行
# (`policy-check.sh`) が**呼ばれる場所を間違えて**いた — 表は `/mule-deploy` の手順と書いていたが、
# 実体は `stage: policy` ゴールの `done_when` だった。**表を見て探した人は見つけられません。**
# 索引と同じで、**ずれた表は無い表より悪い** (書いてあるので確かめずに従う)。だから機械が持つ。
#
# 見るのは 3 つ:
#   1. 表に出てくるスクリプトが実在するか (scripts/ か template/scripts/)
#   2. そのスクリプトが**どこかから呼ばれているか** (hooks/、skills/、agents/、scripts/ のいずれか)
#      — 表に載っているのに誰も呼ばないものは、走らない検査です
#   3. 実在する検査スクリプトが**表に載っているか** — 増やしたのに表に足し忘れると、
#      「どれが自動でどれが手順書任せか」の一覧が嘘になります
#
# 使い方: bash scripts/checks-audit.sh   (exit 0 = 一致、exit 1 = ずれ)
# `/mule-learn --share` は PR を開く前にこれを通す (promote-guard.sh が hook で確かめる)。
set -u
cd "$(dirname "$0")/.." || exit 1

python3 - <<'PY'
import pathlib, re, sys

doc = pathlib.Path("docs/methodology.md")
if not doc.is_file():
    print("checks-audit: docs/methodology.md がありません", file=sys.stderr); sys.exit(1)
text = doc.read_text()
m = re.search(r'## 検査の並び \(走る順\).*?(?=\n## )', text, re.S)
if not m:
    print("checks-audit: 「検査の並び (走る順)」の節が見つかりません", file=sys.stderr); sys.exit(1)
listed = set(re.findall(r'`([a-z0-9-]+\.sh)`', m.group(0)))

# 実体。段 2 / 3 の mvn は表に出るがスクリプトではないので対象外。
def find(name):
    for d in ("scripts", "template/scripts"):
        p = pathlib.Path(d, name)
        if p.is_file(): return p
    return None

CALLERS = [p for d in ("hooks", "skills", "agents", "scripts", "template/tasks")
           for p in pathlib.Path(d).rglob("*") if p.is_file()] if pathlib.Path("hooks").is_dir() else []
blob = {p: p.read_text(errors="ignore") for p in CALLERS}

bad = []
for name in sorted(listed):
    p = find(name)
    if not p:
        bad.append(f"表に `{name}` があるが実体が無い"); continue
    callers = [str(c) for c, t in blob.items() if name in t and c != p]
    if not callers:
        bad.append(f"`{name}` は表に載っているが、どこからも呼ばれていない (走らない検査)")

# 逆方向: 実在する検査が表に載っているか。**検査でないスクリプトは対象外**にする。
NOT_A_CHECK = {
    "plugin-root.sh", "k-new.sh", "schema-index.sh", "add-munit.sh", "done.sh",
    "run-log.sh", "metrics.sh", "cost-report.sh", "munit-coverage-mode.sh",
    "fix-plugin-version.sh", "ch2-public-url.sh", "loop-reminder.sh",
    "checks-audit.sh", "mule-xml-shape.sh", "setup-deps.sh",
}
# mule-xml-shape.sh は quick-check.sh から呼ばれる子で、表では 6b として別行にしている
# (名前が表に出るので listed 側で拾われる)。setup-deps.sh は /mule-setup が外部スキルを
# 入れるためのもので、検査ではない。
for d in ("scripts", "template/scripts"):
    for p in sorted(pathlib.Path(d).glob("*.sh")):
        if p.name in NOT_A_CHECK or p.name in listed:
            continue
        bad.append(f"`{p}` が表に載っていない (検査なら 1 行足す。検査でなければ checks-audit.sh の NOT_A_CHECK に足す)")

if bad:
    print("checks-audit: 表と実体がずれています", file=sys.stderr)
    for b in bad: print(f"  - {b}", file=sys.stderr)
    sys.exit(1)
print(f"checks-audit: 表の {len(listed)} 件すべて、実在して呼ばれている。表に無い検査も無し")
PY
