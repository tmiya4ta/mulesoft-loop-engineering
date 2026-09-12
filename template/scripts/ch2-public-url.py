#!/usr/bin/env python3
"""CloudHub 2.0 のアプリに既定の公開 URL を付けて表示する。

`runtime-mgr application modify --publicEndpoints` は効かない (knowledge/gotchas/deploy.md)。
Application Manager の API で deploymentSettings.generateDefaultPublicUrl を立てる。

使い方: python3 scripts/ch2-public-url.py <app-name> <environment-name>
        python3 scripts/ch2-public-url.py --remove <app-name> <environment-name>
        (環境変数 ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)

`--remove` は**アプリの公開 URL を外します** (`sandbox.yaml` の `ingress: gateway` のとき)。
公開 URL が残ったままゲートウェイを前に置くと、**ゲートウェイを迂回してアプリを直接叩けます** —
ポリシーは効いていないのと同じです (inventory3-api で実測: ゲートウェイ経由は 401、アプリの
公開 URL は認証なしで 200)。外したあと実際に消えたかを読み直して確かめ、消えなければそう言います。

v0.6.44 で bash + curl + jq から Python (標準ライブラリだけ) にした。挙動は同じ。
"""
import json, os, re, sys, time, urllib.error, urllib.request

HOST = os.environ.get("ANYPOINT_HOST", "https://anypoint.mulesoft.com")


def die(msg, code=2):
    print(f"ch2-public-url: {msg}", file=sys.stderr)
    sys.exit(code)


def http(method, path, token=None, body=None):
    req = urllib.request.Request(HOST + path, method=method)
    req.add_header("content-type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data, timeout=60) as r:
            raw = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        die(f"{method} {path} → HTTP {e.code}\n{raw[:800]}")
    except Exception as e:
        die(f"{method} {path} に届かない ({e})")
    try:
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


args = sys.argv[1:]
remove = "--remove" in args
args = [a for a in args if a != "--remove"]
if len(args) < 2:
    die("使い方: ch2-public-url.py [--remove] <app-name> <environment-name>")
app, envname = args[0], args[1]

try:
    pom = open("pom.xml", encoding="utf-8", errors="ignore").read()
except Exception:
    pom = ""
m = re.search(r"<groupId>([0-9a-f-]{36})</groupId>", pom)
if not m:
    die("pom の groupId が組織 ID ではありません")
org = m.group(1)

cid, secret = os.environ.get("ANYPOINT_CLIENT_ID"), os.environ.get("ANYPOINT_CLIENT_SECRET")
if not cid or not secret:
    die("環境変数 ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET が無い")
tok = http("POST", "/accounts/api/v2/oauth2/token",
           body={"grant_type": "client_credentials", "client_id": cid, "client_secret": secret}).get("access_token")
if not tok:
    die("トークン取得に失敗 (Connected App の権限を確認)")

envs = http("GET", f"/accounts/api/organizations/{org}/environments", tok).get("data") or []
env = next((e["id"] for e in envs if e.get("name") == envname), None)
if not env:
    die(f"環境 {envname} が見つかりません")

base = f"/amc/application-manager/api/v2/organizations/{org}/environments/{env}/deployments"
items = http("GET", base, tok).get("items") or []
dep = next((i["id"] for i in items if i.get("name") == app), None)
if not dep:
    die(f"デプロイ {app} が見つかりません")

def public_url_of(dep_json):
    ds = (dep_json.get("target") or {}).get("deploymentSettings") or {}
    return ((ds.get("http") or {}).get("inbound") or {}).get("publicUrl") or ""


cur = http("GET", f"{base}/{dep}", tok)
url = public_url_of(cur)

if remove:
    if not url:
        print(f"ch2-public-url: {app} に公開 URL はありません (ゲートウェイ経由だけの状態)")
        sys.exit(0)
    t = cur.get("target") or {}
    ds = dict(t.get("deploymentSettings") or {})
    inbound = dict(((ds.get("http") or {}).get("inbound") or {}))
    inbound["publicUrl"] = ""
    ds["generateDefaultPublicUrl"] = False
    ds["http"] = {"inbound": inbound}
    http("PATCH", f"{base}/{dep}", tok, {"target": {
        "targetId": t.get("targetId"), "provider": t.get("provider"),
        "replicas": t.get("replicas"), "deploymentSettings": ds}})
    for _ in range(20):
        time.sleep(5)
        if not public_url_of(http("GET", f"{base}/{dep}", tok)):
            print(f"ch2-public-url: {app} の公開 URL ({url}) を外しました")
            print("  ゲートウェイ経由の URL は python3 scripts/gateway-public-url.py <インスタンス> で取る")
            sys.exit(0)
    die(f"公開 URL ({url}) がまだ残っています。Runtime Manager で外してください "
        "(残っているとゲートウェイを迂回できます)", 1)

if not url:
    # 既存の target を保ったまま generateDefaultPublicUrl を足す (modify と違い properties は触らない)
    t = cur.get("target") or {}
    ds = dict(t.get("deploymentSettings") or {})
    inbound = dict(((ds.get("http") or {}).get("inbound") or {}))
    inbound["pathRewrite"] = inbound.get("pathRewrite", "/")
    ds["generateDefaultPublicUrl"] = True
    ds["http"] = {"inbound": inbound}
    http("PATCH", f"{base}/{dep}", tok, {"target": {
        "targetId": t.get("targetId"), "provider": t.get("provider"),
        "replicas": t.get("replicas"), "deploymentSettings": ds}})
    for _ in range(20):
        time.sleep(5)
        cur = http("GET", f"{base}/{dep}", tok)
        url = (((cur.get("target") or {}).get("deploymentSettings") or {}).get("http") or {}).get("inbound", {}).get("publicUrl") or ""
        if url:
            break
if not url:
    die("公開 URL がまだ付きません (Runtime Manager で確認)", 1)

# Application Manager API の publicUrl は **既に https:// を含んで返ることがある**。
# 無条件に付けると `https://https://...` の壊れた URL になる (inventory3-api T-006 で実測)。
if not url.startswith(("http://", "https://")):
    url = "https://" + url
print(url)
