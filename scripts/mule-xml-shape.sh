#!/usr/bin/env bash
# Mule XML の「XSD で落ちる形」を数秒で弾く。**XSD 検証ではありません。**
#
# なぜ XSD 検証ではないのか。コネクタ (db, http, ...) の XSD は jar に**入っていません**。
# jar が持つのは `META-INF/*-extension-descriptions.xml` (説明文だけ) で、XSD はランタイムが
# 拡張モデルから生成します。実測 (2026-09-10): ~/.m2 から抜けた 21 ファイルのうち .xsd は
# ランタイム側だけで、`mule-db-connector.xml` は要素の定義を持たない説明文でした。
# だから `xmllint --schema` では `<db:select>` を検証できません。ここで見るのは
# **台帳に実測がある指紋だけ**です。汎用の検証は `mvn package` (遅い) が受け持ちます。
#
# 見るもの (content model は reference/mule-schema/mule-core-common.xsd の原文から写した):
#   flowType     : description?, messageSource?, processor+, abstract-error-handler?
#   tryType      : processor+, abstract-error-handler?
#   subFlowType  : description?, processor+                       ← error-handler を持てない
#   → `error-handler` は flow / try の **最後の子要素**でなければならず、sub-flow には置けない。
#      `abstract-error-handler` の実体は `error-handler` 1 つだけ (mule-core-common.xsd で確認)。
#   → ルート直下の `<error-handler name="global-error-handler">` は位置の制約が無いので**見ません**
#      (template/reference/global.xml がまさにこの形。ここを弾くと写経元が通らなくなる)。
#   db の操作の SQL は属性ではなく子要素 `<db:sql>` (台帳 T-003、mule-db-connector 1.16.3 で実測)。
#
# 使い方: bash scripts/mule-xml-shape.sh <Mule XML>   → exit 0 = 問題なし / exit 2 = 弾いた
set -u
f=${1:?mule-xml-shape: 対象の XML が必要}

python3 - "$f" <<'PY'
import sys, xml.etree.ElementTree as ET

CORE = "{http://www.mulesoft.org/schema/mule/core}"
DB   = "{http://www.mulesoft.org/schema/mule/db}"
DOC  = "{http://www.mulesoft.org/schema/mule/documentation}"
path = sys.argv[1]

try:
    root = ET.parse(path).getroot()
except Exception:
    sys.exit(0)                    # 形式の壊れは xmllint が先に弾く。ここでは二重に言わない
if root.tag != CORE + "mule":
    sys.exit(0)                    # pom.xml など Mule の設定ファイルでないもの

def label(e):
    n = e.get(DOC + "name") or e.get("name")
    return f'{e.tag.rsplit("}", 1)[-1]}' + (f' ({n})' if n else "")

bad = []
for parent in root.iter():
    kids = list(parent)
    ptag = parent.tag
    for i, e in enumerate(kids):
        if e.tag.startswith(DB) and e.get("sql") is not None:
            bad.append(f'{label(e)} に sql="..." 属性で SQL を書いています。'
                       f'db の操作の SQL は**子要素** <db:sql>...</db:sql> です '
                       f'(属性で書くと XSD 検証で落ちます。写経元: template/reference/resource-impl.xml)')
        if e.tag == CORE + "error-handler":
            if ptag in (CORE + "flow", CORE + "try") and i != len(kids) - 1:
                after = ", ".join(label(k) for k in kids[i + 1:][:3])
                bad.append(f'{label(parent)} の中で <error-handler> の後ろに子要素があります ({after})。'
                           f'content model は (processor)+, (error-handler)? なので '
                           f'**error-handler は最後の子要素**にします')
            if ptag == CORE + "sub-flow":
                bad.append(f'{label(parent)} に <error-handler> を置いています。'
                           f'subFlowType は error-handler を持てません。'
                           f'エラー処理は呼び出し側の flow か <try> に置きます')

if bad:
    print(f"mule-xml-shape: {path} は XSD 検証で落ちる形です", file=sys.stderr)
    for b in bad:
        print(f"  - {b}", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
