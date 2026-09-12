#!/usr/bin/env python3
# PreToolUse(Read) hook。**リポジトリの外にある Mule プロジェクトの設定ファイル**を読むのを止める。
#
# なぜ要るか。CLAUDE.md には「このリポジトリの外の設定値を写さない」と書いてあり、理由も書いてある
# のに、**実際に起きました** (T-001 で、実行エージェントがコネクタの GAV を確かめるつもりで隣の
# プロジェクトの pom.xml を直接 Read した。今回はたまたま同じ組織だったので実害なし)。
# 隣に並んだ Mule プロジェクトの pom.xml には**別の組織の**組織 ID と接続先が書いてあり、
# 「実例を確認する」つもりで写すと**別の組織に publish します**。文章の禁止は破られるので、機械で持つ。
#
# **止めるものを名前で絞ってあります。** 止めるのは Mule プロジェクトの設定ファイルだけ:
#   pom.xml / mule-artifact.json / settings.xml / .mule-deploy.properties
# それ以外は一切見ません。人が指示した資格情報ファイル (`~/.anypoint-env` など) や、
# ドキュメント、ログは**通します** — 汎用の Read guard にすると正当な用途を誤って止めるためです。
#
# 通す場所は 2 つだけ (CLAUDE.md の規則と同じ):
#   (1) このリポジトリの中 (git のルート以下)
#   (2) プラグインの中 (このスクリプトの 1 つ上)
#
# mule-loop のリポジトリでないとき (tasks/ も authorizations.yaml も無い) は何も言いません。
import json
import os
import subprocess
import sys

WATCHED = ("pom.xml", "mule-artifact.json", "settings.xml", ".mule-deploy.properties")

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

path = (data.get("tool_input") or {}).get("file_path") or ""
if not path or os.path.basename(path) not in WATCHED:
    sys.exit(0)

start = data.get("cwd") or os.getcwd()

# mule-loop のリポジトリでなければ介入しない (このプラグインの規則なので、他所には効かせない)
if not (os.path.isdir(os.path.join(start, "tasks"))
        or os.path.isfile(os.path.join(start, "context/deployment/authorizations.yaml"))):
    sys.exit(0)

try:
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=start,
                       capture_output=True, text=True, timeout=30)
    root = (r.stdout or "").strip()
except Exception:
    sys.exit(0)
if not root:
    sys.exit(0)

plugin = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
target = os.path.abspath(path)


def inside(child, parent):
    try:
        return os.path.commonpath([os.path.realpath(child), os.path.realpath(parent)]) == \
            os.path.realpath(parent)
    except Exception:
        return False


if inside(target, root) or inside(target, plugin):
    sys.exit(0)

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason":
        "%s は**このリポジトリの外**にある Mule プロジェクトの設定ファイルです。\n"
        "隣に並んだ別のプロジェクトの pom.xml には**別の組織の**組織 ID と接続先が書いてあり、"
        "「実例を確認する」つもりで写すと**別の組織に publish します** (T-001 で実際に起きました)。\n"
        "読んでよいのは (1) このリポジトリの中 (%s) と (2) プラグインの中 だけです。\n"
        "コネクタの版や GAV を確かめたいなら `reference/mule-schema/INDEX.md` "
        "(`bash scripts/plugin-root.sh reference/mule-schema/INDEX.md`) を見てください。\n"
        "**組織 ID・接続情報・資格情報は人に聞いてください。**分からなければ空のまま止まって聞く。"
        % (target, root),
}}, ensure_ascii=False))
sys.exit(0)
