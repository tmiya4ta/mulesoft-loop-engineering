#!/usr/bin/env python3
# PreToolUse(Edit|Write) hook。波の中で「このゴールが触る」と宣言した追記型ファイルを、
# 進捗エージェント自身が触るのを弾く。
#
# なぜ必要か。並行ゴールに追記型ファイルの分担を宣言したのに、宣言した進捗エージェント自身が
# 配布後に同じファイルへ追記して衝突させた実例がある
# (failures.jsonl: `progress-agent-broke-own-file-ownership`)。
# **宣言は守られる前提で書けない** — 破ったのは宣言した側なので、規則ではなく機械で弾く。
#
# 仕掛け: 進捗エージェントは配布時に `.claude/wave-owned` に「パス<TAB>ゴール id」を 1 行ずつ書き、
# 全ゴールを取り込み終えたら削除する。このファイルは **.gitignore 済みでコミットしない**。
#
# それが「誰を弾くか」をパスの当てずっぽう無しで決めます:
#   - 進捗エージェント → リポジトリ直下で作業する。`.claude/wave-owned` がある → 弾く
#   - 実行エージェント → worktree で作業する。コミットされていないので worktree には無い → 素通り
# `git rev-parse --show-toplevel` は worktree の中では worktree 自身を返すので、
# 上に遡ってリポジトリ直下の `.claude/wave-owned` を拾ってしまうことはありません。
#
# 12 時間より古い `.claude/wave-owned` は無視します。波が中断して消し忘れたファイルが、
# 以降のすべての書き込みを黙って塞ぐのを防ぐため (それ自体が新しい loop-ops になる)。
#
# 限界: 見るのは Edit / Write だけです。`echo >> file` のようなシェル経由の追記は弾けません
# (コマンド文字列からの判定は誤検知が多い)。そこは `/mule-run` の禁止の文章が受け持ちます。
#
# (v0.6.44 で bash + 埋め込み python から python だけにした。bash 版は「python の本体を heredoc で
#  渡すと stdin を食う」ため、hook の JSON を一時ファイルに受けてから渡していた。python だけなら
#  `json.load(sys.stdin)` で直接読めるので、その回り道が要らない。)
import json, os, subprocess, sys, time

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

target = (data.get("tool_input") or {}).get("file_path") or ""
if not target:
    sys.exit(0)
cwd = data.get("cwd") or os.getcwd()

def top(d):
    try:
        r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""

root = top(cwd)
if not root:
    sys.exit(0)

# **リンク worktree では何もしない。** git 自身の信号で判定する: リンク worktree の
# --git-dir は <repo>/.git/worktrees/<名前> で、--git-common-dir (<repo>/.git) と異なる。
# メインの作業ツリーでは一致する。パスの形を推測しないのでレイアウトが変わっても壊れない。
# .gitignore が古くて .claude/wave-owned がコミットされてしまった場合の保険でもある
# (worktree にも現れるが、ここで抜けるので実行エージェントを塞がない)。
def g(*a):
    try:
        r = subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, timeout=10)
        return os.path.realpath(os.path.join(root, r.stdout.strip())) if r.returncode == 0 else ""
    except Exception:
        return ""
if g("rev-parse", "--git-dir") != g("rev-parse", "--git-common-dir"):
    sys.exit(0)

owned = os.path.join(root, ".claude", "wave-owned")
if not os.path.isfile(owned):
    sys.exit(0)                                  # 波が走っていない (または worktree 側)
if time.time() - os.path.getmtime(owned) > 12 * 3600:
    sys.exit(0)                                  # 消し忘れ。塞ぎ続けない

try:
    rel = os.path.relpath(os.path.realpath(os.path.join(cwd, target)), os.path.realpath(root))
except Exception:
    sys.exit(0)
if rel.startswith(".."):
    sys.exit(0)                                  # リポジトリの外

for line in open(owned, encoding="utf-8", errors="ignore"):
    line = line.split("#", 1)[0].strip()
    if not line:
        continue
    parts = line.replace("\t", " ").split()
    path = parts[0]
    goal = parts[1] if len(parts) > 1 else "(ゴール未記入)"
    if os.path.normpath(path) != os.path.normpath(rel):
        continue
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason":
            f"{rel} は今の波で {goal} が触ると宣言した追記型ファイルです "
            f"({owned} に記載)。進捗エージェントは触りません — 宣言した側が破ると"
            "取り込みで衝突します。\n"
            "完了処理の追記は、並行している全ゴールを取り込み終えてからまとめて行ってください。"
            "取り込みが済んでいるなら .claude/wave-owned を削除してから書いてください。"
    }}, ensure_ascii=False))
    sys.exit(0)
sys.exit(0)
