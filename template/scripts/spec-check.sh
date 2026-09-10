#!/usr/bin/env bash
# RAML・サンプル・実装の食い違いのうち、**機械で当てられるもの**を出す。
#
# 走らせる場所は「受け入れ条件を人に承認してもらう前」です (`/mule-run` の手順 3)。
# **承認後に走らせても遅い** — 承認済みのサンプルは「期待値は変えない」の対象になるので、
# 食い違いを見つけても直せるのは実装側だけになります (実例: inventory2-api は承認済みサンプルの
# 不一致に合わせて実装を 2 段構成にした)。承認前なら、サンプルを直すのが一番安い。
# `mule-reviewer` もこれを走らせて指摘に混ぜます (読み取りだけなので害が無い)。
#
# 検査 1: **同じ flow を叩くサンプルの `instance` の形が揃っているか。** exit 2 の対象。
#   どのサンプルがどの flow のものかは MUnit が持っている (`munit:test` の中の `flow-ref` と
#   `readUrl("classpath://samples/...")`)。ファイル名から推測しません
#   (finance-api は `not-found.out.json`、inventory2-api は `reserve-not-found.out.json` で
#    命名規則が違い、名前で当てると片方で機能しません)。
#   根拠: inventory2-api で、同じ `reserve-inventory` を叩く 3 つのサンプルのうち **2 つが
#   `/reserve` を落としていた** (台帳は 1 つとしか記録していなかった)。
#
# 検査 2: **RAML の必須項目が実装のどこにも出てこないか。** こちらは**警告だけ**。
#   通過型 (受けた body をそのまま次の API に渡す) では名前が出てこないのが正常なので、
#   機械では正誤を決められません。**人かレビューエージェントが見る材料**として出します。
#   根拠: inventory2-api で `ReserveRequest.lastUpdated` が必須なのに実装が一切参照しておらず、
#   mule-reviewer が読んで見つけた (RAML 側を削って一致させた)。
set -u
cd "$(dirname "$0")/.." || exit 1

python3 - <<'PY'
import json, pathlib, re, sys, collections
import xml.etree.ElementTree as ET

MUNIT = "{http://www.mulesoft.org/schema/mule/munit}"
CORE  = "{http://www.mulesoft.org/schema/mule/core}"
rc = 0

# ---- 検査 1: 同じ flow のサンプルの instance の形 --------------------------------
def deep_instance(o):
    if isinstance(o, dict):
        v = o.get("instance")
        if isinstance(v, str):
            return v
        for x in o.values():
            r = deep_instance(x)
            if r:
                return r
    return None

by_flow = collections.defaultdict(dict)
for f in sorted(pathlib.Path("src/test/munit").glob("*.xml")) if pathlib.Path("src/test/munit").is_dir() else []:
    try:
        root = ET.parse(f).getroot()
    except Exception:
        continue
    for test in root.iter(MUNIT + "test"):
        blob = ET.tostring(test, encoding="unicode")
        flows = re.findall(r'<(?:\w+:)?flow-ref[^>]*name="([^"]+)"', blob)
        outs = re.findall(r'classpath://(samples/[^"\']+\.out\.json)', blob)
        for fl in set(flows):
            for o in set(outs):
                by_flow[fl][o] = None

bad1 = []
for flow, samples in sorted(by_flow.items()):
    shapes = {}
    for s in sorted(samples):
        p = pathlib.Path(s)
        if not p.is_file():
            continue
        try:
            v = deep_instance(json.loads(p.read_text()))
        except Exception:
            v = None
        if v:
            shapes[s] = (v, len([x for x in v.split("/") if x]))
    counts = {n for _, n in shapes.values()}
    if len(counts) > 1:
        bad1.append((flow, shapes))

if bad1:
    rc = 2
    print("spec-check: 同じ flow を叩くサンプルの instance の形が揃っていません", file=sys.stderr)
    for flow, shapes in bad1:
        print(f"  flow {flow}:", file=sys.stderr)
        for s, (v, n) in sorted(shapes.items(), key=lambda kv: kv[1][1]):
            print(f"    {n} 段  {v}   ({s})", file=sys.stderr)
        print("    → 承認前なら**サンプルを揃える**のが一番安い。承認後は「期待値は変えない」に", file=sys.stderr)
        print("      縛られ、実装側で辻褄を合わせることになります。", file=sys.stderr)
else:
    print(f"spec-check: instance の形は flow ごとに揃っている ({len(by_flow)} flow)")

# ---- 検査 2: RAML の必須項目が実装に出てくるか (警告のみ) ------------------------
try:
    import yaml
except Exception:
    print("spec-check: PyYAML が無いので検査 2 は飛ばします", file=sys.stderr)
    sys.exit(rc)

class Loose(yaml.SafeLoader):
    pass
Loose.add_multi_constructor("!", lambda l, s, n: None)

ramls = sorted(pathlib.Path("api").glob("*.raml")) if pathlib.Path("api").is_dir() else []
impl = ""
for d in ("src/main/mule", "src/main/resources/dwl"):
    for f in pathlib.Path(d).rglob("*") if pathlib.Path(d).is_dir() else []:
        if f.is_file():
            impl += f.read_text(errors="ignore")

def required_props(t):
    props = (t or {}).get("properties") or {}
    out = []
    for name, spec in props.items():
        if name.endswith("?"):
            continue
        if isinstance(spec, dict) and spec.get("required") is False:
            continue
        out.append(name)
    return out

def walk(node, types, path, found):
    if not isinstance(node, dict):
        return
    for k, v in node.items():
        if isinstance(k, str) and k.startswith("/"):
            walk(v, types, path + k, found)
        elif k in ("get", "post", "put", "patch", "delete") and isinstance(v, dict):
            body = v.get("body")
            names = []
            if isinstance(body, dict):
                for mt, spec in body.items():
                    if isinstance(spec, dict) and isinstance(spec.get("type"), str):
                        names.append(spec["type"])
                    elif isinstance(spec, str):
                        names.append(spec)
                if isinstance(body.get("type"), str):
                    names.append(body["type"])
            for tn in names:
                if tn in types:
                    for prop in required_props(types[tn]):
                        found.append((f"{k.upper()} {path}", tn, prop))

warn = []
for r in ramls:
    try:
        doc = yaml.load(r.read_text(), Loader=Loose) or {}
    except Exception as e:
        print(f"spec-check: {r} を読めません ({e})。検査 2 は飛ばします", file=sys.stderr)
        doc = {}
    types = doc.get("types") or {}
    found = []
    walk(doc, types, "", found)
    for where, tn, prop in found:
        if not re.search(rf'\b{re.escape(prop)}\b', impl):
            warn.append((where, tn, prop))

if warn:
    print("spec-check: RAML が必須にしている項目が実装に出てきません (**警告。機械では正誤を決められません**)", file=sys.stderr)
    for where, tn, prop in warn:
        print(f"  {where} の {tn}.{prop}", file=sys.stderr)
    print("  → 受けた body をそのまま次に渡す通過型なら、名前が出てこないのが正常です。", file=sys.stderr)
    print("    そうでなければ、RAML が要求しているのに読んでいないということです", file=sys.stderr)
    print("    (実例: ReserveRequest.lastUpdated。RAML 側を削って一致させた)。", file=sys.stderr)
else:
    print("spec-check: RAML の必須項目はすべて実装に出てくる")

sys.exit(rc)
PY
