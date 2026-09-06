#!/usr/bin/env bash
# UserPromptSubmit hook。mule-loop のリポジトリ (tasks/ がある) なら、毎ターン規律を短く注入する。
# スキルの手順書は起動時に 1 回しか読まれず要約で薄れるので、消えない場所に置く。
[ -d tasks ] || exit 0
open=$(grep -l '^status: *\(todo\|failed\|running\)' tasks/T-*.md 2>/dev/null | wc -l)
blocked=$(grep -l '^status: *blocked' tasks/T-*.md 2>/dev/null | wc -l)
cat <<EOT
[mule-loop] 未完了ゴール ${open} 件、blocked ${blocked} 件。規律: (1) 台帳の外で作業しない。done_when の無い作業は先にゴールにする。(2) マニュアルを読まない。足りない事実は実行エージェントに調べさせ knowledge/ に書かせる。(3) 人に聞くのは decisions.yaml の一括質問と 4 つのゲートだけ。迷ったら既定で進み仮定として記録。(4) 人の用件を済ませたあと、未完了ゴールがあり人の判断が要らないなら /mule-run の手順で次を配る。止まるなら「現在地 / 次にすること / そのあと」の 3 ブロックで締め、次にすることは 1 つ。
EOT
exit 0
