#!/usr/bin/env python3
# PreToolUse(Bash) hook。Sandbox へのデプロイを「人が毎回押す承認」ではなくファイルで判定する。
#
# 判定者を人から機械に移すのがこのリポジトリの作り方なので、デプロイだけ人の Enter に
# 頼っているのは筋が通らない。許可はもともと context/deployment/authorizations.yaml に
# 書いてある。それを読んで allow / deny を返す。
#
#   deploy.sandbox が allowed でない            → deny (ファイルを直すのは人)
#   環境名が Production 系、または空で確認できない → deny (本番は常に人が手で行う)
#   両方満たす                                   → allow (プロンプト無しで通す)
#
# 環境名は sandbox.yaml と pom.xml の両方を見る。実際に mvn が使うのは pom なので、
# sandbox.yaml が Sandbox でも pom が Production を指していれば止める。
#
# ★探す起点は hook 入力の cwd で、そこから git ルートまで遡って authorizations.yaml を探す。
#   相対パスで開くと、monorepo や worktree で作業ディレクトリがプロジェクト直下でないとき
#   ファイルを見つけられず、無言で素通り (= 無防備なデプロイ) になる。v0.6.7 で実際に
#   踏んだ相対パス解決の事故と同じ形。コマンドが絶対パスへ `cd` してから走る形 (mule-run が
#   実行エージェントに配る形) なら、その `cd` 先を起点にする。
#   遡っても見つからなければ mule-loop のリポジトリではないので、何も言わずに通常の許可判定へ返す。
import json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from casual_mode import casual          # noqa: E402

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command") or ""
if not cmd:
    sys.exit(0)

# デプロイのコマンドでなければ介入しない (`mvn mule:deploy` / `deploy:deploy` の形も捕まえる)
DEPLOY = re.compile(r"(mvn[^;|&]*([\s:]deploy|-DmuleDeploy)|anypoint-cli(-v4)?[^;|&]*\sdeploy)")
if not DEPLOY.search(cmd):
    sys.exit(0)

start = data.get("cwd") or ""
m = re.search(r"^[ \t]*cd[ \t]+([^;&|\n]*)", cmd, re.M)
if m:
    cdto = m.group(1).strip().strip("\"'").rstrip()
    if cdto.startswith("/") and os.path.isdir(cdto):
        start = cdto
if not start:
    start = os.getcwd()

mode = casual(start)
root, d = "", start
while d:
    if os.path.isfile(os.path.join(d, "context/deployment/authorizations.yaml")):
        root = d
        break
    if os.path.exists(os.path.join(d, ".git")):   # git ルートまで来た = このリポジトリには無い
        break
    parent = os.path.dirname(d)
    if parent == d:
        break
    d = parent
if not root:
    if mode is None or mode.get("deploy") != "allowed":
        sys.exit(0)                               # mule-loop のリポジトリでなければ何も言わない
    root = os.path.dirname(os.path.dirname(mode["_path"]))   # <root>/context/casual.yaml → <root>
auth = os.path.join(root, "context/deployment/authorizations.yaml")


def say(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def read(path):
    try:
        return open(path, encoding="utf-8", errors="ignore").read()
    except Exception:
        return ""


# authorizations.yaml の deploy: ブロックから sandbox: の値だけ取る (policy: の同名キーと混ぜない)
allowed = ""
in_deploy = False
for line in read(auth).splitlines():
    if re.match(r"^deploy:", line):
        in_deploy = True
        continue
    if re.match(r"^[^\s#]", line):
        in_deploy = False
    if in_deploy:
        m = re.match(r"^\s+sandbox:(.*)$", line)
        if m:
            allowed = re.sub(r"[\s\"]", "", m.group(1).split("#", 1)[0])
            break

# **カジュアルモードは許可ファイルの代わりになる** (`deploy: allowed` を書いたときだけ)。
# 期限つきで、人が自分の手で入れたものなので「人が明示的に許可した」条件は満たしている。
# **本番系の環境名は下でこの後も必ず見る。** そこはカジュアルでも緩めない。
if allowed != "allowed" and mode is not None and mode.get("deploy") == "allowed":
    allowed = "allowed"
if allowed != "allowed":
    say("deny",
        f"{auth} の deploy.sandbox が「{allowed or '未設定'}」です。"
        "デプロイの許可はこのファイルにしか無く、書き換えるのは人です。\n"
        "Sandbox に置いてよいなら deploy.sandbox: allowed にしてから、もう一度このコマンドを流してください。")

env_sb = ""
m = re.search(r"^environment:[ \t]*([^#\n]*)", read(os.path.join(root, "context/deployment/sandbox.yaml")), re.M)
if m:
    env_sb = re.sub(r"[ \"]", "", m.group(1))
env_pom = ""
m = re.search(r"<environment>([^<]*)</environment>", read(os.path.join(root, "pom.xml")))
if m:
    env_pom = m.group(1).replace(" ", "")

# Production 系の名前。prd は Anypoint でよく使う略記なので prod と別に見る。
PROD = re.compile(r"prod|(^|[^a-z])prd([^a-z]|$)|本番", re.I)
for e in (env_sb, env_pom):
    if e and PROD.search(e):
        say("deny",
            f"デプロイ先の環境名が「{e}」です。本番は常に人が Runtime Manager から手で行うので、"
            "このループは Production 系の環境には向けません。\n"
            f"Sandbox に置くつもりなら {root}/context/deployment/sandbox.yaml の environment と "
            "pom.xml の <environment> を確かめてください。")

if not (env_sb + env_pom):
    say("deny",
        "デプロイ先の環境名が context/deployment/sandbox.yaml にも pom.xml にも無く、"
        "Sandbox かどうか確かめられません。\n"
        "sandbox.yaml の environment を書いてから流してください (空のまま通すと本番に向く事故が止められません)。")

# 許可はある。最後に **jar に秘密が混入していないか**見る。
# `-DattachMuleSources` はプロジェクト全体を丸ごと jar に入れ `.gitignore` を見ないので、
# **publish したあとに気付いても取り返せない** (Exchange に上がった時点で組織の全員から見える)。
# 手順書は `mvn clean package` の直後に `jar-leak-check.sh` を呼ぶが、**呼び忘れても
# 気付けない**ので、jar が既にあるならここでも見る。無ければ何も言わない (これから作るので)。
leak_check = os.path.join(root, "scripts/jar-leak-check.sh")
import glob
if os.path.isfile(leak_check) and glob.glob(os.path.join(root, "target/*.jar")):
    try:
        r = subprocess.run(["bash", "scripts/jar-leak-check.sh"], cwd=root,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
        if r.returncode == 2:
            say("deny",
                "target/ にある jar に **git が無視しているファイル** が入っています。"
                "publish すると Exchange に上がり、組織の全員から見えます。\n\n"
                + (r.stdout or "").rstrip("\n") +
                "\n秘密を持つファイルはプロジェクトの外 (例: ~/<app>-credential、パーミッション 600) に置き、"
                "jar を削除して作り直してください。\n"
                "**.gitignore は jar には効きません** (-DattachMuleSources はファイルシステムを丸ごと入れる)。")
    except Exception:
        pass

say("allow", f"deploy.sandbox: allowed / 環境「{env_pom or env_sb}」。{auth} の許可で通しました。")
