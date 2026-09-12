#!/usr/bin/env python3
"""この組織の**開発環境**を Anypoint から読み出して、sandbox.yaml に書く形と、人に 1 回で聞くことを出す。

なぜ必要か。デプロイの直前になって「どの環境か」「Private Space か共有スペースか」「そもそも
Flex Gateway を持っているのか」が分からず、そのたびに止まって人に聞いていた (inventory3-api T-006
で 5 往復)。**これらは全部 API から読めます。** 読んでから、選ぶところだけを 1 回で聞く。

読むもの (すべて GET。何も変えません):
  /accounts/api/organizations/{org}/environments          環境 (production かどうかも分かる)
  /runtimefabric/api/organizations/{org}/targets          デプロイ先 (shared-space / private-space / runtime-fabric)
  /apimanager/xapi/v1/.../gateway-targets                 Flex Gateway (managed / selfManaged)

使い方:
  python3 scripts/env-probe.py                 # 全部出す
  python3 scripts/env-probe.py --env Sandbox   # 環境を 1 つに絞る
資格情報と組織の解決は anypoint-api.py と同じ (ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET)。

exit 0 = 出せた / 2 = 前提が無い (資格情報、組織 ID)
"""
import json, os, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent


def api(path, env=None):
    """anypoint-api.py に投げて JSON で返す。取れなければ None (止めない)。"""
    e = dict(os.environ)
    if env:
        e["ANYPOINT_ENV"] = env
    r = subprocess.run([sys.executable, str(HERE / "anypoint-api.py"), path],
                       capture_output=True, text=True, env=e, timeout=120)
    if r.returncode != 0:
        return None, (r.stderr or "").strip()
    try:
        return json.loads(r.stdout), ""
    except Exception:
        return None, "応答が JSON ではありません"


def vkey(v):
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3] or [0])


args = sys.argv[1:]
want_env = None
if "--env" in args:
    want_env = args[args.index("--env") + 1]

envs, err = api("/accounts/api/organizations/{org}/environments")
if envs is None:
    print("env-probe: 環境一覧が取れません。" + err, file=sys.stderr)
    sys.exit(2)
rows = envs.get("data") or []

print("== 環境 (この組織で見えるもの)")
for e in rows:
    mark = "  ← 本番。このループは使わない" if e.get("isProduction") else ""
    print(f"  {e.get('name'):<20} {e.get('type','')}{mark}")
sandbox_envs = [e["name"] for e in rows if not e.get("isProduction")]
env_name = want_env or (sandbox_envs[0] if sandbox_envs else None)

print()
print("== デプロイ先 (kind と target に書くもの)")
targets, err = api("/runtimefabric/api/organizations/{org}/targets")
tnames = []
if targets is None:
    print("  取れません。" + err)
else:
    for t in targets:
        vs = []
        for r in t.get("runtimes", []):
            if r.get("type") == "mule":
                vs = sorted({v["baseVersion"] for v in r.get("versions", [])}, key=vkey, reverse=True)[:3]
        kind = {"shared-space": "cloudhub2", "private-space": "cloudhub2",
                "runtime-fabric": "rtf"}.get(t.get("type"), "?")
        tnames.append((t.get("name"), t.get("type"), kind, vs[0] if vs else ""))
        print(f"  {t.get('name'):<24} {t.get('type'):<15} kind: {kind:<10} "
              f"{t.get('region',''):<15} mule {', '.join(vs)}")

print()
print(f"== Flex Gateway ({env_name or '環境が決まっていない'})")
gws = []
if env_name:
    g, err = api("/apimanager/xapi/v1/organizations/{org}/environments/{env}/gateway-targets", env=env_name)
    if g is None:
        print("  取れません。" + err)
    else:
        for row in g.get("rows") or []:
            gws.append(row)
            ready = "使える" if row.get("ready") else "まだ使えない"
            print(f"  {row.get('name'):<24} {row.get('kind','?'):<12} {row.get('status','')} ({ready})"
                  f"  target: {row.get('targetType','')}")
        if not gws:
            print("  **この環境に Flex Gateway はありません。**")
            print("  → ゲートウェイ経由 (ingress: gateway) は選べません。公開エンドポイント (ingress: public) にするか、")
            print("    人にゲートウェイを用意してもらってください (Runtime Manager → Flex Gateways)。")

print()
print("== sandbox.yaml に書く形 (**書くのは人**。この形をそのまま渡す)")
# 既定の提案は CloudHub 2.0 を先に (Private Space → 共有スペース → RTF の順)。このループの既定が CH2 のため。
order = {"private-space": 0, "shared-space": 1, "runtime-fabric": 2}
first = sorted(tnames, key=lambda t: order.get(t[1], 9))[0] if tnames else ("<target>", "", "cloudhub2", "")
print(f"  kind: {first[2]}")
print(f"  environment: {env_name or '<環境名>'}")
print(f"  target: {first[0]}        # 上の一覧から選ぶ")
print(f"  mule_version: {first[3] or '<版>'}        # その target が対応している版から選ぶ")
print("  ingress: public          # public = アプリに公開 URL を付ける / gateway = 付けず Flex Gateway 経由だけ")
print(f"  gateway: \"{gws[0]['name'] if gws else ''}\"" + ("" if gws else "               # ingress: gateway のときだけ"))

print()
print("== 人に 1 回でまとめて聞くこと")
print(f"  1. 環境は {env_name or '?'} でよいか (他の候補: {', '.join(n for n in sandbox_envs if n != env_name) or '無し'})")
print(f"  2. デプロイ先はどれか ({', '.join(t[0] for t in sorted(tnames, key=lambda t: order.get(t[1], 9))[:6])}"
      f"{' …' if len(tnames) > 6 else ''})")
print("  3. **公開エンドポイントを付けるか**")
print("     - 付ける (ingress: public)   … アプリの URL を直接叩く。そのままでよいならこちら")
print("     - 付けない (ingress: gateway) … アプリに公開 URL を付けず、Flex Gateway 経由だけにする。")
print("       ポリシー (認証・流量) をゲートウェイで効かせるならこちら。**迂回路が無いのはこちらだけ**")
if gws:
    print(f"       使えるゲートウェイ: {', '.join(r.get('name','?') for r in gws)}")
else:
    print("       → この環境にゲートウェイが無いので、今は「付ける」しか選べません")
sys.exit(0)
