#!/usr/bin/env bash
# ~/.m2 の jar から、このプロジェクトが実際に使う版のコネクタ定義とランタイム XSD を抜き出し、
# reference/mule-schema/ に置く。エージェントがコネクタのパラメータ名や要素名を推測しないための地の情報。
#
# なぜ生成するのか。コネクタの XSD と説明は jar の META-INF に入っていて、版ごとに中身が違う。
# 手で書き写すと版がずれ、gotchas.md の「コネクタの GAV を推測しない」を人間の側で破ることになる。
# jar から抜けば、そのプロジェクトが実際に解決した版と必ず一致する。
#
# 依存は bash + python3 + mvn だけ。**Node は使わない** (Windows も macOS も既定で入っておらず、
# このプラグインの既存の前提は bash + python3 + jq なので、依存を増やす理由が無い。
# jar は zip なので python3 の zipfile で直接読める)。
#
# 一覧は `mvn -o dependency:list` から取る。pom を正規表現で読むと `${...}` の版と、
# 推移的に入るコネクタ (mule-sockets-connector など) を落とす。**ネットワークには触らない。**
# ~/.m2 に無いものは取りに行かず、INDEX.md の「未解決」に並べる。
#
# 出力は git にコミットする。worktree は origin/main から切られるので、コミットしていないものは
# 実行エージェントに届かない (v0.6.7 の実測)。版が変わったことが diff で見えるという利点もある。
#
# exit 0 = 生成した。exit 2 = 前提が無い (pom.xml が無い / mvn が無い / 依存が未解決)。
set -u

[ -f pom.xml ] || { echo "schema-index: pom.xml が無い (/mule-init が済んでいない)" >&2; exit 2; }
command -v mvn >/dev/null 2>&1 || { echo "schema-index: mvn が無い" >&2; exit 2; }

deps=$(mktemp); trap 'rm -f "$deps"' EXIT
# スコープは絞らない。-DincludeScope=compile を付けると MUnit (test スコープ) と
# db コネクタが一覧から消える。
if ! mvn -o -q -Dstyle.color=never dependency:list -DoutputFile="$deps" >/dev/null 2>&1; then
  echo "schema-index: mvn -o dependency:list が失敗した。" >&2
  echo "  先に \`mvn -q clean package -DskipTests\` を通して ~/.m2 を埋めてください。" >&2
  exit 2
fi

python3 - "$deps" reference/mule-schema <<'PY'
import os, re, sys, glob, zipfile, pathlib

deps_file, out = sys.argv[1], pathlib.Path(sys.argv[2])
m2 = pathlib.Path.home() / ".m2" / "repository"
ANSI = re.compile(r'\x1b\[[0-9;]*m')
# 欲しいのは 3 種類。コネクタの説明 (パラメータ名と説明文)、XSD (要素と属性の型)、
# 名前空間から XSD への対応表 (mule.schemas)。
WANT = re.compile(r'^META-INF/(?:.*/)?(?:[^/]*extension-descriptions\.xml|[^/]+\.xsd|mule\.schemas)$')

def vkey(v):
    return [int(x) if x.isdigit() else 0 for x in re.split(r'[.\-]', v)[:4]]

def resolve(g, a, v):
    """指定の版が ~/.m2 に無ければ、同じ major.minor の最新、無ければ全体の最新を使う。
    minMuleVersion (4.12.0) と実際に置かれている版 (4.12.2) がずれるため。"""
    base = m2.joinpath(*g.split(".")) / a
    if (base / v).is_dir():
        return v
    if not base.is_dir():
        return None
    have = sorted((d.name for d in base.iterdir() if d.is_dir()), key=vkey)
    if not have:
        return None
    mm = ".".join(v.split(".")[:2]) + "."
    same = [x for x in have if x.startswith(mm)]
    return (same or have)[-1]

# --- 1. 解決済み GAV を dependency:list から取る (g:a:type[:classifier]:version:scope) ---
gavs, seen = [], set()
def add(g, a, v):
    if (g, a) not in seen:
        seen.add((g, a)); gavs.append((g, a, v))

for line in pathlib.Path(deps_file).read_text(errors="ignore").splitlines():
    line = ANSI.sub("", line).split(" -- ")[0].strip()
    p = line.split(":")
    if len(p) == 5:   g, a, v = p[0], p[1], p[3]
    elif len(p) == 6: g, a, v = p[0], p[1], p[4]
    else: continue
    if not re.fullmatch(r'[\w.\-]+', v or ""): continue
    add(g, a, v)

# --- 2. ランタイムの extension model は依存一覧に出てこない (ランタイムが提供する) ---
pom = pathlib.Path("pom.xml").read_text(errors="ignore")
m = re.search(r'<app\.runtime>([^<]+)</app\.runtime>', pom)
rt = m.group(1).strip() if m else None
if not rt and pathlib.Path("mule-artifact.json").exists():
    m = re.search(r'"minMuleVersion"\s*:\s*"([^"]+)"',
                  pathlib.Path("mule-artifact.json").read_text(errors="ignore"))
    rt = m.group(1).strip() if m else None
if rt:
    add("org.mule.runtime", "mule-runtime-extension-model", rt)
    add("com.mulesoft.mule.runtime.modules", "mule-runtime-ee-extension-model", rt)

# --- 3. 抜き出す。前回の生成物は消してから (版が変わったとき古いファイルが残らないように) ---
out.mkdir(parents=True, exist_ok=True)
for f in out.iterdir():
    if f.is_file() and (f.suffix in (".xml", ".xsd") or f.name in ("mule.schemas", "INDEX.md")):
        f.unlink()

rows, missing, catalog = [], [], []
for g, a, v in gavs:
    rv = resolve(g, a, v)
    if rv is None:
        # Mule のものだけ「未解決」として報告する。spring や commons は元から関係ない。
        if g.startswith(("org.mule", "com.mulesoft")):
            missing.append((g, a, v))
        continue
    jars = sorted(glob.glob(str(m2.joinpath(*g.split(".")) / a / rv / "*.jar")))
    for jar in jars:
        try: z = zipfile.ZipFile(jar)
        except Exception: continue
        for e in z.namelist():
            if not WANT.match(e): continue
            body = z.read(e).decode("utf-8", "replace")
            name = e.split("/")[-1]
            if name == "mule.schemas":
                # 複数の jar が同名で持っている (runtime / ee / munit)。上書きし合うので 1 本に統合する。
                catalog.append(f"# {g}:{a}:{rv}\n{body.rstrip()}")
                continue
            if name.endswith("extension-descriptions.xml"):
                name = f"{a}.xml"          # database-extension-descriptions.xml → mule-db-connector.xml
                kind = "定義"
            elif name.endswith(".xsd"):
                kind = "XSD"
            else:
                kind = "対応表"
            # GAV は XML 宣言の**後ろ**に入れる (前に置くと well-formed でなくなり xmllint が落ちる)
            note = f"<!-- mule-loop schema-index: {g}:{a}:{rv} / {e} -->"
            if body.lstrip().startswith("<?xml"):
                i = body.index("?>") + 2
                body = body[:i] + "\n" + note + body[i:]
            elif name.endswith((".xml", ".xsd")):
                body = note + "\n" + body
            (out / name).write_text(body)
            rows.append((a, rv, name, kind, body.count("\n") + 1))

if catalog:
    txt = ("# 名前空間 → XSD の対応表。schema-index.sh が複数の jar の mule.schemas を統合したもの。\n"
           + "\n".join(catalog) + "\n")
    (out / "mule.schemas").write_text(txt)
    rows.append(("(統合)", "-", "mule.schemas", "対応表", txt.count("\n")))

# --- 4. INDEX.md。全部読ませないための索引なので、何がどこにあるかだけ書く ---
def ops(name):
    """定義ファイルに入っている操作名。エージェントが開く前に当たりを付けられるように。"""
    try: t = (out / name).read_text(errors="ignore")
    except Exception: return ""
    n = re.findall(r'<operation name="([^"]+)"', t)
    if not n: return ""
    head = ", ".join(n[:8])
    return head + (f" … 他 {len(n)-8}" if len(n) > 8 else "")

L = ["# Mule スキーマ索引 (自動生成)", "",
     "`scripts/schema-index.sh` が `~/.m2` の jar から抜いたもの。**手で編集しない** (再生成で消える)。",
     "`pom.xml` を変えたら再生成する (`preflight.sh` が自動で行う)。", "",
     "**全部読まない。** 使うコネクタの行のファイルだけを開く。パラメータ名と説明が要るときは `定義` の",
     "`.xml`、要素と属性の型が要るときは `XSD`。名前空間から XSD への対応は `mule.schemas`。", ""]
if rows:
    L += ["| artifactId | version | ファイル | 中身 | 行数 |", "|---|---|---|---|---|"]
    for a, v, n, k, ln in sorted(rows):
        L.append(f"| {a} | {v} | [{n}]({n}) | {k} | {ln:,} |")
    L.append("")
    od = [(a, n, ops(n)) for a, v, n, k, ln in sorted(rows) if k == "定義"]
    od = [x for x in od if x[2]]
    if od:
        L += ["## 操作の一覧 (定義ファイルの中身)", ""]
        for a, n, o in od:
            L.append(f"- **{a}** (`{n}`): {o}")
        L.append("")
else:
    L += ["**1 つも抜き出せなかった。** `mvn -q clean package -DskipTests` を通してから再実行する。", ""]
if missing:
    L += ["## 未解決 (`~/.m2` に無い)", "",
          "取りに行かない (このスクリプトはネットワークに触らない)。必要なら `mvn -q clean package",
          "-DskipTests` を通してから再実行する。", "",
          "| groupId | artifactId | version |", "|---|---|---|"]
    for g, a, v in sorted(missing):
        L.append(f"| {g} | {a} | {v} |")
    L.append("")
(out / "INDEX.md").write_text("\n".join(L))

print(f"schema-index: {len(rows)} ファイルを {out}/ に生成 "
      f"({sum(r[4] for r in rows):,} 行)。未解決 {len(missing)} 件。")
PY
