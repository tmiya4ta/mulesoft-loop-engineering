#!/usr/bin/env python3
"""CloudHub 2.0 / RTF に置いたアプリの状態を出す。**RUNNING なら exit 0。**

なぜ必要か。`ingress: gateway` (アプリに公開 URL を付けない) のとき、deploy ゴールの done_when に
公開 URL への疎通が使えません (外から叩けないのが正しい状態なので)。代わりに「置けて動いているか」を
機械で答えるのがこのスクリプトです。`anypoint-cli-v4 runtime-mgr application describe` と同じことを
Platform API で行うので、CLI が入っていなくても動きます。

使い方:
  python3 scripts/app-status.py <app-name> [<environment>]        # 今の状態を 1 行
  python3 scripts/app-status.py <app-name> [<environment>] --wait 600   # RUNNING になるまで待つ (秒)
環境名を省くと context/deployment/sandbox.yaml の environment を使います。
資格情報は ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET。

exit 0 = RUNNING (または APPLIED / STARTED) / 1 = それ以外 (FAILED、まだ来ない) / 2 = 前提が無い
"""
import json, os, re, sys, time, urllib.error, urllib.request

HOST = os.environ.get("ANYPOINT_HOST", "https://anypoint.mulesoft.com")
OK = {"RUNNING", "APPLIED", "STARTED"}


def die(msg, code=2):
    print(f"app-status: {msg}", file=sys.stderr)
    sys.exit(code)


def http(path, token=None):
    req = urllib.request.Request(HOST + path)
    req.add_header("content-type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8", "replace") or "{}")
    except urllib.error.HTTPError as e:
        die(f"GET {path} → HTTP {e.code}\n{e.read().decode('utf-8', 'replace')[:500]}")
    except Exception as e:
        die(f"GET {path} に届かない ({e})")


def token():
    cid, sec = os.environ.get("ANYPOINT_CLIENT_ID"), os.environ.get("ANYPOINT_CLIENT_SECRET")
    if not cid or not sec:
        die("環境変数 ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET が無い")
    req = urllib.request.Request(HOST + "/accounts/api/v2/oauth2/token", method="POST")
    req.add_header("content-type", "application/json")
    body = json.dumps({"grant_type": "client_credentials", "client_id": cid, "client_secret": sec}).encode()
    try:
        with urllib.request.urlopen(req, body, timeout=60) as r:
            return json.loads(r.read().decode()).get("access_token")
    except Exception as e:
        die(f"トークンが取れない ({e})")


args = sys.argv[1:]
wait = 0
if "--wait" in args:
    i = args.index("--wait")
    wait = int(args[i + 1])
    args = args[:i] + args[i + 2:]
if not args:
    die("使い方: app-status.py <app-name> [<environment>] [--wait <秒>]")
app = args[0]
envname = args[1] if len(args) > 1 else ""
if not envname:
    try:
        y = open("context/deployment/sandbox.yaml", encoding="utf-8", errors="ignore").read()
        m = re.search(r"^environment:[ \t]*([^#\n]*)", y, re.M)
        envname = (m.group(1).strip().strip('"') if m else "")
    except Exception:
        pass
if not envname:
    die("環境名が分かりません (引数か sandbox.yaml の environment)")

try:
    pom = open("pom.xml", encoding="utf-8", errors="ignore").read()
except Exception:
    pom = ""
m = re.search(r"<groupId>([0-9a-f-]{36})</groupId>", pom)
org = os.environ.get("ANYPOINT_ORG") or (m.group(1) if m else "")
if not org:
    die("組織 ID が分かりません (pom の groupId か ANYPOINT_ORG)")

tok = token()
envs = http(f"/accounts/api/organizations/{org}/environments", tok).get("data") or []
env = next((e["id"] for e in envs if e.get("name") == envname), None)
if not env:
    die(f"環境 {envname} が見つかりません")
base = f"/amc/application-manager/api/v2/organizations/{org}/environments/{env}/deployments"

deadline = time.time() + wait
while True:
    items = http(base, tok).get("items") or []
    d = next((i for i in items if i.get("name") == app), None)
    if d is None:
        st, detail = "見つからない", f"この環境に {app} という配備がありません"
    else:
        st = (d.get("application") or {}).get("status") or d.get("status") or "?"
        ts = d.get("lastModifiedDate")
        when = time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime(ts / 1000)) if isinstance(ts, (int, float)) else "?"
        detail = f"{d.get('name')}  {st}  (更新 {when})"
    if st in OK or time.time() >= deadline:
        break
    time.sleep(15)

print(f"app-status: {detail}")
if st in OK:
    sys.exit(0)
if st not in ("見つからない",):
    print("  FAILED なら Runtime Manager のログを見る (properties 不足、Java 版、接続先)", file=sys.stderr)
sys.exit(1)
