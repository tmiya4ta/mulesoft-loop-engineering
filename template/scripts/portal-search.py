#!/usr/bin/env python3
# Anypoint にある値の**項目名**から、それを応答で返す Platform API の操作を引く。
# 公式ポータル (dev-portal.mulesoft.com) の全 API 仕様 (OpenAPI、36 本) を手元に写して探す。
#
# なぜ必要か。「API から取れない」と決めて人に画面を見てもらった値が、実は API の応答に
# そのまま載っていた (inventory3-api T-007、2026-09-11)。Managed Flex Gateway の公開 URL は
# Gateway Manager API の `getGatewayById` の `configuration.ingress.publicUrl` にある。
# 試したのは API Manager と CloudHub 2.0 (Private Space) だけで、残りの API を見ていなかった。
# このスクリプトで `publicUrl` を引くと 36 本中 2 本に絞れる。
# **探し方を知らないことを「取れない」と書かない。** 人に画面を見てもらうのは、これで外れてから。
#
# 使い方:
#   python3 scripts/portal-search.py publicUrl       # 項目名。大文字小文字は区別しない。部分一致
#   python3 scripts/portal-search.py dnsTarget
#   python3 scripts/portal-search.py --refresh       # 写しを取り直す (既定では 7 日たつと取り直す)
# 出るもの (API ごと):
#   - 当たった項目の場所 (スキーマ名.項目) と、**それを応答で返す操作**
#   - GET の操作は、そのまま流せる `python3 scripts/anypoint-api.py '<パス>' --find <項目名>` の行
#   - パスに残る変数 ({gatewayId} など) の値をどの操作から取るか (仕様の x-origin)
#
# **仕様に載っていない項目もあります。** CloudHub 2.0 の Private Space の `dnsTarget` や
# `inboundStaticIps` は実際の応答にはあるのに、公式の仕様には書かれていません。外れたら
# 「関係しそうな API の一覧か詳細の GET を叩き、応答から `--find` で探す」に進みます (外れたときに出ます)。
#
# 写しの置き場所: ${XDG_CACHE_HOME:-~/.cache}/mule-loop/portal/ (約 11MB。初回だけ数秒かかる)。
# 依存は python3 の標準ライブラリだけ。YAML は字下げで読む (PyYAML は要らない)。
#
# exit 0 = 当たった / 1 = どこにも無い (次の手を出す) / 2 = ポータルに届かず写しも無い
#
# --- bash 版 (portal-search.py) からの移植メモ -------------------------------------------
# 中身は元から Python なので、bash の包み (set -u と python3 - "$@" <<'PY') を外しただけ。
# 探索の本体・キャッシュの場所・7 日で取り直す条件・出力は 1 文字も変えていない。
import concurrent.futures as cf, json, os, pathlib, re, sys, time, urllib.request

BASE = "https://dev-portal.mulesoft.com"
cache = pathlib.Path(os.environ.get("XDG_CACHE_HOME") or pathlib.Path.home() / ".cache") / "mule-loop" / "portal"
args = sys.argv[1:]
refresh = "--refresh" in args
args = [a for a in args if a != "--refresh"]
q = (args[0] if args else "").strip()
if not q and not refresh:
    print("使い方: portal-search.py '<項目名>'   例: publicUrl / dnsTarget / targetId", file=sys.stderr)
    sys.exit(2)

def get(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None

def norm(path):
    out = []
    for s in path.split("/"):
        if s == "..":
            if out: out.pop()
        elif s not in ("", "."):
            out.append(s)
    return "/".join(out)

def sync():
    reg = get(BASE + "/registry.json")
    if reg is None:
        return False
    todo = [e["href"].lstrip("/") for e in json.loads(reg) if e.get("kind") == "oas"]
    seen, n = set(), 0
    while todo:
        batch = [h for h in dict.fromkeys(todo) if h not in seen]
        todo = []
        seen.update(batch)
        with cf.ThreadPoolExecutor(16) as ex:
            for h, t in zip(batch, ex.map(lambda h: get(f"{BASE}/{h}"), batch)):
                if t is None:
                    continue
                p = cache / h
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(t)
                n += 1
                # **`./` を付けない参照も拾う。** 公式の api.yaml は `$ref: schemas/x.yaml#/Y` と
                # 書く方が多く、`\.{1,2}/` を要求していた版では**別ファイルを 1 つも取れていなかった**。
                # 症状: `#/components/...` (同一ファイル) だけが辿れ、**POST の本文の必須項目が
                # 引けない** (exchange-experience の CreateContractV2 が schemas/ にある形)。
                # 拾わないもの: `#` 始まり (同一ファイル内) と絶対 URL。
                for ref in set(re.findall(r"\$ref:\s*['\"]?([^\s'\"#][^\s'\"#]*)", t)):
                    if re.match(r"^[a-z][a-z0-9+.-]*://", ref):
                        continue
                    todo.append(norm(str(pathlib.PurePosixPath(h).parent / ref)))
    if n:
        (cache / "registry.json").write_text(reg)
        (cache / ".stamp").write_text(str(time.time()))
    return n > 0

stamp = cache / ".stamp"
stale = refresh or not stamp.is_file() or time.time() - float(stamp.read_text() or 0) > 7 * 86400
if stale:
    print("portal-search: 公式ポータルの API 仕様を写しています (初回は数秒)...", file=sys.stderr)
    if not sync():
        if stamp.is_file():
            print("portal-search: ポータルに届かないので、前回の写しで探します", file=sys.stderr)
        else:
            print(f"portal-search: {BASE} に届かず、写しもありません (ネットワークを確かめる)", file=sys.stderr)
            sys.exit(2)
if not q:
    print(f"portal-search: 写しを取り直しました ({cache})")
    sys.exit(0)

# ---- YAML (と整形済み JSON) を字下げで読む ---------------------------------------------
YKEY = re.compile(r"^(\s*)(-\s+)?(['\"]?)(.+?)\3:(?:\s+(.*))?$")
JKEY = re.compile(r"^(\s*)()(\")([^\"]+)\":\s*(.*)$")
class Doc:
    def __init__(self, path):
        self.path = path
        self.rel = str(path.relative_to(cache))
        key = JKEY if path.suffix == ".json" else YKEY
        self.keys = []          # (行番号, 列, キー, 値)
        block = None            # ブロックスカラー (| や >) の中は読まない
        for i, line in enumerate(path.read_text(errors="ignore").splitlines()):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            ind = len(line) - len(line.lstrip())
            if block is not None:
                if ind > block:
                    continue
                block = None
            m = key.match(line)
            if not m:
                continue
            col = len(m.group(1)) + len(m.group(2) or "")
            val = (m.group(5) or "").strip()
            self.keys.append((i + 1, col, m.group(4), val))
            if re.match(r"^[|>][-+0-9]*$", val):
                block = col
        self.parent, stack = [], []
        for k, (_, col, _, _) in enumerate(self.keys):
            while stack and self.keys[stack[-1]][1] >= col:
                stack.pop()
            self.parent.append(stack[-1] if stack else None)
            stack.append(k)

    def names(self, k):
        out = []
        while k is not None:
            out.append(k)
            k = self.parent[k]
        return out[::-1]

    def child(self, k, key):
        col = self.keys[k][1]
        for j in range(k + 1, len(self.keys)):
            if self.keys[j][1] <= col:
                break
            if self.parent[j] == k and self.keys[j][2] == key:
                return self.keys[j][3].strip("'\"")
        return None

STRUCT = {"properties", "items", "allOf", "oneOf", "anyOf", "additionalProperties", "schema",
          "content", "application/json", "*/*"}
METHODS = {"get", "post", "put", "patch", "delete"}

def locate(doc, k):
    """k の位置を ('op', method, path, where, 操作の k) か ('node', 参照される名前, 表示) で返す。
    参照される名前は `schemas/Name` (#/components/... で参照される) か `file:<パス>` (ファイル丸ごと)。"""
    ch = doc.names(k)
    names = [doc.keys[c][2] for c in ch]
    if names and names[0] == "paths" and len(names) == 2:
        return ("path", names[1], ch[1])
    if names and names[0] == "paths" and len(names) >= 3 and names[2] in METHODS:
        where = ("応答" if "responses" in names else
                 "要求" if ("requestBody" in names or "parameters" in names) else "説明")
        return ("op", names[2].upper(), names[1], where, ch[2])
    if len(names) >= 3 and names[0] == "components":
        field = ".".join(n for n in names[3:] if n not in STRUCT)
        return ("node", f"{names[1]}/{names[2]}", names[2] + (f".{field}" if field else ""))
    field = ".".join(n for n in names if n not in STRUCT)
    return ("node", f"file:{doc.rel}", f"{doc.path.name} の {field}" + ("  (例)" if doc.path.suffix == ".json" else ""))

def xorigin(docs, var):
    """パスの変数 {var} の値をどの操作から取るか (仕様の x-origin)。"""
    for d in docs:
        for k, (_, col, key, val) in enumerate(d.keys):
            if key == "name" and val.strip("'\"") == var:
                op = vals = None
                for j in range(k + 1, len(d.keys)):
                    if d.keys[j][1] < col:
                        break
                    if d.keys[j][2] == "operation" and not op: op = d.keys[j][3]
                    if d.keys[j][2] == "values" and not vals: vals = d.keys[j][3]
                if op:
                    return f"{op} の {vals or '?'}"
    return None

# ---- 探す -----------------------------------------------------------------------------
reg = json.loads((cache / "registry.json").read_text())
apis = [e for e in reg if e.get("kind") == "oas"]
ql = q.lower()
found = 0

for e in apis:
    slug = e["slug"]
    root = cache / "apis" / slug
    if not root.is_dir():
        continue
    docs = [Doc(p) for p in sorted(root.rglob("*")) if p.suffix in (".yaml", ".yml", ".json")]
    main = next((d for d in docs if d.path.name == "api.yaml" and d.path.parent == root), None)
    if main is None:
        continue
    hits = [(d, k) for d in docs for k, (_, _, key, _) in enumerate(d.keys) if ql in key.lower()]
    loose = False
    if not hits:
        hits = [(d, k) for d in docs if d.path.suffix != ".json" for k, (_, _, key, val) in enumerate(d.keys)
                if key in ("description", "summary") and ql in val.lower()]
        loose = True
    if not hits:
        continue

    # $ref の索引: 参照される名前 → [(doc, k)]
    refs = {}
    for d in docs:
        for k, (_, _, key, val) in enumerate(d.keys):
            if key != "$ref":
                continue
            v = val.strip("'\"")
            m = re.search(r"#/components/([^/]+)/(\S+)$", v)
            if m:
                refs.setdefault(f"{m.group(1)}/{m.group(2)}", []).append((d, k))
            elif "#" not in v and v.startswith("."):
                tgt = norm(str(pathlib.PurePosixPath(d.rel).parent / v))
                refs.setdefault(f"file:{tgt}", []).append((d, k))

    ops, fields = {}, []
    for d, k in hits:
        loc = locate(d, k)
        if loc[0] == "path":        # リソースの名前 (privatespaces、gateways) で引いたとき
            for k2 in range(loc[2] + 1, len(d.keys)):
                if d.parent[k2] == loc[2] and d.keys[k2][2] in METHODS:
                    ops.setdefault((d.keys[k2][2].upper(), loc[1]), [d, k2, set()])[2].add("パス")
            fields.append(f"パス {loc[1]}  ({d.rel}:{d.keys[k][0]})")
            continue
        if loc[0] == "op":
            ops.setdefault((loc[1], loc[2]), [d, loc[4], set()])[2].add(loc[3])
            fields.append(f"{loc[1]} {loc[2]} の {'説明' if loose else d.keys[k][2]}  ({d.rel}:{d.keys[k][0]})")
            continue
        fields.append(f"{loc[2]}  ({d.rel}:{d.keys[k][0]})")
        todo, seen = [(loc[1], 0)], set()
        while todo:
            node, depth = todo.pop()
            if node in seen or depth > 8:
                continue
            seen.add(node)
            for rd, rk in refs.get(node, []):
                rl = locate(rd, rk)
                if rl[0] == "op":
                    ops.setdefault((rl[1], rl[2]), [rd, rl[4], set()])[2].add(rl[3])
                else:
                    todo.append((rl[1], depth + 1))
    found += 1
    server = next((v for _, _, key, v in main.keys if key == "url" and v.startswith("http")), "")
    prefix = re.sub(r"^https?://[^/]+", "", server.strip("'\"")).rstrip("/")
    print(f"━━ {slug} — {e.get('name', '')}" + ("   (項目名には無く、説明文に出てくる)" if loose else ""))
    ys = [f for f in dict.fromkeys(fields) if not f.endswith("(例)") and "(例)  (" not in f]
    # **api.yaml 以外のヒットも必ず見せる。** 6 件で切ると api.yaml の項目だけが並び、
    # `schemas/` にある**要求の本文の必須項目が一度も出ない** (実測: exchange-experience の
    # versionGroup。POST の本文が引けず、契約の作り方が分からないまま止まった)。
    # api.yaml から 5 件、それ以外のファイルから 3 件までを別々に取る。
    shown = ys or list(dict.fromkeys(fields))
    main_rel = main.rel
    from_main = [f for f in shown if f"({main_rel}:" in f]
    others = [f for f in shown if f"({main_rel}:" not in f]
    # **schemas/ を examples/ より先に出す。** 必須項目 (required) が書いてあるのは schemas の方で、
    # examples はただの値の例。本文を書くために引いているので、先に見せるべきなのは schemas。
    others.sort(key=lambda f: (0 if "/schemas/" in f else 1 if "/examples/" not in f else 2))
    for f in from_main[:5] + others[:3]:
        print(f"   項目: {f}")
    rank = lambda w: 0 if "応答" in w else 1 if "パス" in w else 2
    resp = sorted(((m, p) for (m, p), v in ops.items() if v[2] & {"応答", "説明", "パス"}),
                  key=lambda x: (x[0] != "GET", rank(ops[x][2]), x[1]))
    gets = [(m, p) for m, p in resp if m == "GET"]
    # 応答の形が仕様に無く、作る操作 (POST /x) の要求にだけ出てくるなら、同じパスの詳細 GET が返すことが多い
    if not gets:
        allops = [(k2, d) for d in docs if d is main for k2, (_, col, key, _) in enumerate(d.keys)
                  if col == 4 and key in METHODS and d.keys[d.parent[k2]][1] == 2]
        for m, p in [mp for mp, v in ops.items() if "要求" in v[2]]:
            for k2, d in allops:
                gp = d.keys[d.parent[k2]][2]
                if d.keys[k2][2] == "get" and re.fullmatch(re.escape(p) + r"(/\{[^}/]+\})?", gp):
                    ops.setdefault(("GET", gp), [d, k2, {"推測"}])
                    gets.append(("GET", gp))
    for m, p in (resp + [g for g in gets if g not in resp])[:8]:
        d, opk, where = ops[(m, p)]
        opid = d.child(opk, "operationId") or "?"
        label = ("返す操作" if "応答" in where else "たぶん返す操作 (仕様に応答の形が無い)" if "推測" in where
                 else "パスに出てくる操作" if "パス" in where else "説明に出てくる操作")
        print(f"   {label}: {m} {p}   {opid}")
        if m == "GET":
            path = prefix + re.sub(r"\{(organizationId|orgId)\}", "{org}", re.sub(r"\{(environmentId|envId)\}", "{env}", p))
            print(f"     python3 scripts/anypoint-api.py '{path}'" + (f" --find {q}" if where & {"応答", "推測"} else ""))
            for var in dict.fromkeys(re.findall(r"\{([^}]+)\}", path)):
                if var in ("org", "env"):
                    continue
                src = xorigin(docs, var)
                print(f"       {{{var}}} の値: " + (f"{src} (同じ API の一覧の操作で取る)" if src else "同じ API の一覧の操作 (list...) の応答から取る"))
    if not resp and not gets:
        others = sorted({f"{m} {p}" for (m, p) in ops})
        print("   応答で返す操作は仕様から辿れません" + (f" (要求で使う操作: {', '.join(others[:3])})" if others else ""))
    print()

if found:
    print(f"portal-search: '{q}' は {found} 本の API に出てきます。")
    print("  GET の行をそのまま流して、実際の応答で確かめる (パスの {...} は「の値」の行の操作で先に取る)。")
    print("  取れたら bash scripts/k-new.sh <ゴール id> が出したパスに「どの API のどの項目か」を書く。")
    sys.exit(0)
print(f"portal-search: '{q}' は公式の API 仕様 {len(apis)} 本のどの項目名にも説明文にもありません。")
print("**仕様に書かれていない項目もあります** (例: Private Space の dnsTarget は応答にあるが仕様に無い)。次にすること (この順で):")
print("  1. 別の言い方で引き直す。項目名は camelCase の英語 (例: publicUrl → url / host / endpoint / domain)")
print("  2. 関係しそうな API の一覧か詳細の GET を叩き、実際の応答から探す:")
print(f"       python3 scripts/anypoint-api.py '<パス>' --find {q}")
print("     パスは、その値を持っていそうなもの (ゲートウェイ、Private Space、アプリ) の名前で portal-search を引いて得る")
print("  3. それでも無ければ、そこで初めて人に聞く。そのとき**引いた語と叩いたパスを全部**添える")
print("  **やってはいけない**: 1 本か 2 本の API を見ただけで「API では取れない」と書く")
sys.exit(1)
