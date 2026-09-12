#!/usr/bin/env python3
# 段 1 の検証器: 編集されたファイルに応じて数秒で終わる検査だけを行う。
# 失敗は stderr と exit 2 で Claude Code に返す (hook の規約)。
import json, os, pathlib, re, subprocess, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

file = (data.get("tool_input") or {}).get("file_path") or ""
if not file or not os.path.isfile(file):
    sys.exit(0)


def fail(msg):
    print(f"quick-check: {msg}", file=sys.stderr)
    sys.exit(2)


def have(cmd):
    from shutil import which
    return which(cmd) is not None


def run(*cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return 1, str(e)


def head(text, n):
    return "\n".join(text.splitlines()[:n])


path = pathlib.PurePosixPath(file.replace("\\", "/"))

if file.endswith(".dwl"):
    if have("dw"):
        # dw CLI に単体の -f は無い。検査は `dw validate -f`。
        # そのうえで validate は 2 つの誤判定を出す。どちらも Mule の dwl では正常な形。
        #   1. module (--- を持たないファイル) に "Missing Mapping Expression" と言う
        #      → 変換を module に切り出すのは規則 5 が求める形
        #   2. payload / vars / attributes / p() を "Unable to resolve reference" にする
        #      → 実行時にしかない束縛なので当然
        # module の本物の構文エラーは正しく捕まる (fun f(x) = x + → Missing addition expression) ので、
        # 上の 2 つを除いた残りの [ERROR] があるときだけ弾く。
        _, out = run("dw", "validate", "-f", file)
        out = re.sub(r"\x1b\[[0-9;]*m", "", out)
        ignore = re.compile(
            r"Missing Mapping Expression"
            r"|Unable to resolve reference of: `(payload|vars|attributes|error|correlationId"
            r"|authentication|app|flow|server|mule|p)`")
        real = [l for l in out.splitlines() if "[ERROR]" in l and not ignore.search(l)]
        if real:
            fail("DataWeave の構文エラー: " + head("\n".join(real), 3))

elif re.search(r"/src/main/mule/[^/]*\.xml$", str(path)):
    if have("xmllint"):
        rc, out = run("xmllint", "--noout", file)
        if rc != 0:
            fail("Mule XML が壊れています: " + head(out, 3))
    # XSD で落ちる形 (db の SQL を属性で書く、error-handler の位置)。台帳に実測がある指紋だけを見る。
    # **XSD 検証ではない** — コネクタの XSD は jar に入っていないので xmllint --schema は使えない。
    # 詳しい理由と content model の出所は scripts/mule-xml-shape.sh の冒頭に書いてある。
    shape = pathlib.Path(__file__).resolve().parent / "mule-xml-shape.sh"
    if shape.is_file():
        rc, out = run("bash", str(shape), file)
        if rc != 0:
            fail(out.rstrip("\n"))

    # 層の越境: kind: api で System 層以外から DB / SAP コネクタを直接使っていないか。
    # kind 行が無い既存リポジトリ (v0.6.0 以前に /mule-init したもの) は api とみなす (後方互換)。
    # batch は DB を直接触るのが正常な形なので、kind: batch ではこの検査自体をしない。
    kind = layer = ""
    try:
        md = pathlib.Path("CLAUDE.md").read_text(errors="ignore")
        m = re.search(r"^kind:[ \t]*(.*)$", md, re.M)
        kind = m.group(1).strip() if m else ""
        m = re.search(r"^layer:[ \t]*(.*)$", md, re.M)
        layer = m.group(1).strip() if m else ""
    except Exception:
        pass
    kind = kind or "api"
    if kind == "api" and layer and layer != "system":
        body = pathlib.Path(file).read_text(errors="ignore")
        if re.search(r"<db:|<sap:|<salesforce:", body):
            fail(f"{layer} 層から System コネクタを直接使っています。System API 経由にしてください。")

elif re.search(r"/tasks/T-[^/]*\.md$", str(path)) or re.match(r"^tasks/T-.*\.md$", file):
    body = pathlib.Path(file).read_text(errors="ignore")
    if not re.search(r"^done_when:[ \t]*\S", body, re.M):
        fail(f"ゴール {file} に done_when がありません。done_when の無いゴールは作れません。")

sys.exit(0)
