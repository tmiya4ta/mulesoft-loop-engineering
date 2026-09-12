#!/usr/bin/env python3
"""カジュアルモードを入れる / 切る / 見る。**ちょっと試したいときだけ。**

台帳も TDD も許可ファイルも要らない状態にします。**期限つき**で、既定は 8 時間。
過ぎたら自動で通常モードに戻ります (切り忘れた緩みは誰にも見えないため)。

使い方:
  python3 scripts/casual.py on              # 8 時間。デプロイは許可しない
  python3 scripts/casual.py on --hours 2    # 2 時間
  python3 scripts/casual.py on --deploy     # Sandbox へのデプロイも authorizations.yaml 無しで通す
  python3 scripts/casual.py status
  python3 scripts/casual.py off

**緩むもの**
  - 台帳 (tasks/T-*.md) と TDD の強制。ゴールを切らずに直接書いてよい
  - 3 ブロックの締めと「まだ進められる」の差し戻し
  - 層の越境の検査 (構文の検査は残る)
  - **git が無視するファイルへの秘密の書き込み** (パスワードを渡して設定に書かせられる)
  - `--deploy` を付けたときだけ、Sandbox へのデプロイの許可ファイル要求

**緩まないもの (ここが緩むと取り返しがつかない)**
  - 本番系の環境名へのデプロイは常に deny
  - publish 前の jar の混入検査 (Exchange に上げたら組織の全員から見える)
  - **追跡されているファイル**への秘密の書き込み (git に入ると履歴から消せない)

exit 0 = できた / 2 = 使い方が違う
"""
import datetime, os, pathlib, sys

CFG = pathlib.Path("context/casual.yaml")
GITIGNORE = pathlib.Path(".gitignore")


def ensure_ignored():
    """**git が無視することを先に確かめる。** ここが漏れると、秘密を書いた設定ごとコミットされる。"""
    line = "context/casual.yaml"
    txt = GITIGNORE.read_text(errors="ignore") if GITIGNORE.is_file() else ""
    if line not in txt:
        GITIGNORE.write_text(txt + ("" if txt.endswith("\n") or not txt else "\n")
                             + "\n# カジュアルモードの印。**コミットしない**\ncontext/casual.yaml\n")
        print(f"casual: .gitignore に {line} を足しました")


def alive():
    """期限内なら True。**hook 側 (scripts/casual_mode.py) と同じ判定をここでも持つ。**
    プラグイン側のモジュールを import しようとして失敗し、効いているのに「期限切れ」と
    嘘をついた (実測)。判定は 6 行なので、借りずに持つ。"""
    if not CFG.is_file():
        return False
    for line in CFG.read_text(errors="ignore").splitlines():
        if line.startswith("expires:"):
            try:
                when = datetime.datetime.fromisoformat(line.split(":", 1)[1].strip().replace("Z", "+00:00"))
                if when.tzinfo is None:
                    when = when.replace(tzinfo=datetime.timezone.utc)
                return when > datetime.datetime.now(datetime.timezone.utc)
            except Exception:
                return False
    return False                                   # 期限の無いカジュアルモードは認めない


def status():
    if not CFG.is_file():
        print("casual: 通常モードです (context/casual.yaml はありません)")
        return 0
    body = CFG.read_text(errors="ignore").strip()
    if not alive():
        print("casual: ファイルはありますが**効いていません** (期限切れ)。入れ直すなら on")
    else:
        print("casual: **カジュアルモードです**")
    print("\n".join("  " + l for l in body.splitlines() if l.strip() and not l.startswith("#")))
    return 0


args = sys.argv[1:]
verb = args[0] if args else "status"

if verb == "status":
    sys.exit(status())

if verb == "off":
    if CFG.is_file():
        CFG.unlink()
        print("casual: 通常モードに戻しました (台帳・TDD・許可ファイルが戻ります)")
    else:
        print("casual: もともと通常モードです")
    sys.exit(0)

if verb != "on":
    print(__doc__.split("使い方:")[1].split("**緩むもの**")[0].strip(), file=sys.stderr)
    sys.exit(2)

hours = 8
if "--hours" in args:
    hours = float(args[args.index("--hours") + 1])
deploy = "--deploy" in args
until = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=hours)

CFG.parent.mkdir(parents=True, exist_ok=True)
ensure_ignored()
CFG.write_text(
    "# カジュアルモードの印。**このファイルは git に入れない** (.gitignore 済み)。\n"
    "# 期限を過ぎたら自動で通常モードに戻ります。切るのは python3 scripts/casual.py off\n"
    f"expires: {until.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
    f"deploy: {'allowed' if deploy else 'denied'}\n"
    f"created_by: casual.py\n")
print(f"casual: **カジュアルモード** ({hours} 時間、{until.strftime('%H:%M')}Z まで)")
print("  緩むもの: 台帳と TDD の強制 / 3 ブロックの締め / 層の越境の検査 /")
print("            **git が無視するファイルへの秘密の書き込み**"
      + (" / Sandbox へのデプロイ" if deploy else ""))
print("  緩まないもの: 本番へのデプロイ / publish 前の jar 検査 / **追跡ファイルへの秘密の書き込み**")
if not deploy:
    print("  デプロイもしたいなら: python3 scripts/casual.py on --deploy")
print("  戻すとき: python3 scripts/casual.py off")
