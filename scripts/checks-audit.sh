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
#   1. 表に出てくるスクリプトが実在するか (scripts/ か template/scripts/。.sh でも .py でも)
#   2. そのスクリプトが**どこかから呼ばれているか** (hooks/、skills/、agents/、scripts/ のいずれか)
#      — 表に載っているのに誰も呼ばないものは、走らない検査です
#   3. 実在する検査スクリプトが**表に載っているか** — 増やしたのに表に足し忘れると、
#      「どれが自動でどれが手順書任せか」の一覧が嘘になります
#
# 使い方: bash scripts/checks-audit.sh   (exit 0 = 一致、exit 1 = ずれ)
# `/mule-learn --share` は PR を開く前にこれを通す (promote-guard.py が hook で確かめる)。
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
listed = set(re.findall(r'`([a-z0-9-]+\.(?:sh|py))`', m.group(0)))

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
# **このリストは私が手で分類したので、取りこぼしが起きます。** 実際に 3 件間違えました:
#   - `done.sh` を入れていた → **これは検査です** (`done_when` を回して終了コードを返す = 表の 11)。
#     除外していたので、表に載っていなくても気付けませんでした。
#   - `checks-audit.sh` と `mule-xml-shape.sh` を入れていた → **表に載っているので冗長**。
#     載っているものは下の `p.name in listed` で先に抜けます。両方に書くと「検査ではない」と
#     読めてしまいます。
# だから残すのは「表に載せる必要が無い」と言い切れるものだけにします。判断の基準は
# **「exit コードで合否を答えるか」** です。答えるなら検査で、表に載せます。
NOT_A_CHECK = {
    "plugin-root.sh",         # パスを解決して出す (見つからなければ exit 1 だが合否ではない)
    "k-new.sh",               # 次の K ファイルの名前を出す
    "schema-index.sh",        # ~/.m2 から索引を生成する
    "add-munit.sh",           # pom に MUnit を足す
    "munit-coverage-mode.sh", # pom にカバレッジゲートを入れるかを決める
    "fix-plugin-version.sh",  # pom の mule-maven-plugin の版を直す
    "ch2-public-url.py",      # CH2 の公開 URL を取って出す
    "gateway-public-url.py",  # Flex Gateway に置いた API の公開 URL を出す (exit 1 は「外からの URL が無い」)
    "anypoint-api.py",        # Platform API を GET して応答を出す (exit 1 は HTTP の失敗で、合否ではない)
    "portal-search.py",       # 項目名から、それを返す API の操作を引く (exit 1 は「仕様に無い」)
    "policy.py",              # ポリシーを探す/見る/付ける/外す (合否は policy-check.sh が答える)
    "contract.py",            # 消費アプリと契約を作る (合否は policy-check.sh が答える)
    "env-probe.py",           # 環境・デプロイ先・ゲートウェイを読み出して出す (合否を答えない)
    "run-log.sh",             # 1 行記録する
    "metrics.sh",             # 4 指標を出す
    "cost-report.sh",         # 実コストを出す
    "loop-reminder.py",       # UserPromptSubmit hook。規律を注入する (合否を答えない)
    "setup-deps.sh",          # /mule-setup が外部スキルと MCP を入れる
    "gotcha-lookup.sh",       # 既知の地雷を引く。exit 1 は「書いていない」で、合否ではない
    "run-hook.sh",            # hook を起動するだけの包み (python の名前を吸収する。判定はしない)
    "casual_mode.py",         # カジュアルモードが効いているかを hook が読む共通の判定 (単体では何も判定しない)
    "casual.py",              # カジュアルモードを入れる/切る/見る (合否を答えない)
}
for d in ("scripts", "template/scripts"):
    for p in sorted(list(pathlib.Path(d).glob("*.sh")) + list(pathlib.Path(d).glob("*.py"))):
        if p.name in NOT_A_CHECK or p.name in listed:
            continue
        bad.append(f"`{p}` が表に載っていない (検査なら 1 行足す。検査でなければ checks-audit.sh の NOT_A_CHECK に足す)")

if bad:
    print("checks-audit: 表と実体がずれています", file=sys.stderr)
    for b in bad: print(f"  - {b}", file=sys.stderr)
    sys.exit(1)
print(f"checks-audit: 表の {len(listed)} 件すべて、実在して呼ばれている。表に無い検査も無し")
PY
