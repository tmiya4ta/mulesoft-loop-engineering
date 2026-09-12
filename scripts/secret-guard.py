#!/usr/bin/env python3
# PreToolUse(Edit|Write) hook。**秘密の値そのものがリポジトリのファイルに書かれるのを弾く。**
#
# なぜ必要か。デモ用の資格情報を、進捗確認のコメントとして**追跡されている 3 ファイルに書き込みかけた**
# 実例がある (failures.jsonl: `credential-written-to-repo-file`)。自分で grep して消したので値は
# 残らなかったが、**気付いたのは書いたあと**だった。台帳の fix は「コミット前に grep する運用を
# 徹底する」だったが、それは規則で、破った側が自分で守る話になる。だから機械で弾く。
#
# **パターンで秘密を当てません。** `password` や `secret` という語を探すやり方は誤検知が多く、
# 値が変数名を含まないと素通りします。ここでは **値そのものを照合します** — 秘密が正しく
# 置かれている場所から読んで、それが書き込み内容に現れたら弾く。だから
#   - 変数名や書式に依存しない (base64 でも UUID でも引っかかる)
#   - 秘密でない文字列を弾かない (誤検知がほぼ無い)
#
# 照合元 (秘密が正しく置かれている場所):
#   - 環境変数 ANYPOINT_CLIENT_SECRET / ANYPOINT_CLIENT_ID (`/mule-deploy` はここからしか読まない)
#   - ~/.m2/settings.xml の <password>
# 8 文字未満の値は使いません (短い値はふつうの文字列と衝突するため)。
#
# **値は絶対に出力しません。** 出すのは「どのファイルに、どの置き場所の値が現れたか」だけです。
# hook の出力は会話に入るので、そこに値を書いたら弾く意味が無くなります。
#
# 限界: 見るのは Edit / Write の書き込み内容だけです。`echo >> file` のようなシェル経由は弾けません
# (Bash の hook は deploy-guard が使っており、コマンド文字列からの判定は誤検知が多い)。
import json, os, pathlib, re, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = data.get("tool_input") or {}
target = ti.get("file_path") or ""
if not target:
    sys.exit(0)
# Write は content、Edit は new_string。どちらも「これから入る文字列」。
content = "".join(str(ti.get(k) or "") for k in ("content", "new_string"))
if not content.strip():
    sys.exit(0)

# 秘密が正しく置かれている場所から値を集める。**ここで集めた値は一切出力しない。**
secrets = {}
for name in ("ANYPOINT_CLIENT_SECRET", "ANYPOINT_CLIENT_ID"):
    v = os.environ.get(name) or ""
    if len(v) >= 8:
        secrets[v] = f"環境変数 ${name}"
try:
    st = pathlib.Path(os.path.expanduser("~/.m2/settings.xml")).read_text(errors="ignore")
    for v in re.findall(r"<password>([^<]+)</password>", st):
        v = v.strip()
        # ${env.X} のような参照は秘密の値ではない
        if len(v) >= 8 and not v.startswith("${"):
            secrets.setdefault(v, "~/.m2/settings.xml の <password>")
except Exception:
    pass

if not secrets:
    sys.exit(0)

hits = sorted({src for v, src in secrets.items() if v in content})
if not hits:
    sys.exit(0)

rel = target
try:
    r = os.path.relpath(target, os.getcwd())
    if not r.startswith(".."):      # cwd の外は絶対パスのままにする (../../.. は読みにくい)
        rel = r
except Exception:
    pass

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason":
        f"{rel} に書こうとしている内容に、秘密の値が**そのまま**含まれています "
        f"(出所: {', '.join(hits)})。\n"
        "**値は出しません** (hook の出力も会話に入るため)。\n"
        "秘密はファイルに書かず、参照にしてください — pom なら ${env.ANYPOINT_CLIENT_ID} / "
        "${env.ANYPOINT_CLIENT_SECRET}、設定なら secure プロパティ、"
        "接続先の資格情報はプロジェクトの外 (例: ~/<app>-credential、パーミッション 600) に置きます。\n"
        "進捗のメモに値を貼る必要はありません。「どこから読むか」を書いてください。"
}}, ensure_ascii=False))
sys.exit(0)
