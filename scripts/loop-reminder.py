#!/usr/bin/env python3
# UserPromptSubmit hook。mule-loop のリポジトリ (tasks/ がある) なら、毎ターン規律を短く注入する。
# スキルの手順書は起動時に 1 回しか読まれず要約で薄れるので、消えない場所に置く。
import pathlib, re, sys

if not pathlib.Path("tasks").is_dir():
    sys.exit(0)

OPEN = re.compile(r"^status: *(todo|failed|running)", re.M)
BLOCKED = re.compile(r"^status: *blocked", re.M)
open_n = blocked_n = 0
for p in sorted(pathlib.Path("tasks").glob("T-*.md")):
    t = p.read_text(errors="ignore")
    if OPEN.search(t):
        open_n += 1
    if BLOCKED.search(t):
        blocked_n += 1

print(
    f"[mule-loop] 未完了ゴール {open_n} 件、blocked {blocked_n} 件。"
    "規律: (1) 台帳の外で作業しない。done_when の無い作業は先にゴールにする。"
    "(2) マニュアルを読まない。足りない事実は実行エージェントに調べさせ knowledge/ に書かせる。"
    "(3) 人に聞くのは decisions.yaml の一括質問と 4 つのゲートだけ。迷ったら既定で進み仮定として記録。"
    "(4) 人の用件を済ませたあと、未完了ゴールがあり人の判断が要らないなら /mule-run の手順で次を配る。"
    "止まるなら「現在地 / 次にすること / そのあと」の 3 ブロックで締め、次にすることは 1 つ。"
)
sys.exit(0)
