#!/usr/bin/env python3
"""hook 7 本が、決めた入力に対して決めた判定を返すかを確かめる。**プラグインのリポジトリで走らせる。**

なぜ必要か。hook は**効かなくなっても誰も気付きません** (セッション開始時に読まれ、失敗しても
そのツール呼び出しが通るだけ)。fixtures-check.sh は XML の形 (mule-xml-shape) だけを見ており、
deny を返す hook 本体には自動のテストがありませんでした。v0.6.44 で 7 本を bash から Python に
書き換えたとき、**書き換え前後で同じ判定になることを 28 ケースで突き合わせた**ので、その突き合わせを
期待値として残します。以後、hook を直したらここが落ちます。

見るのは (終了コード, 何を出したか) の 2 つだけです。文面までは固定しません
(文面を変えるたびにテストを直すと、テストが目的になるため)。

使い方: python3 scripts/hooks-check.py    (exit 0 = 全ケース期待どおり / 1 = 違う)
`/mule-learn --share` は PR を開く前にこれを通す (promote-guard.py が hook でも確かめる)。
"""

import json, os, pathlib, shutil, subprocess, sys, tempfile

REPO = pathlib.Path("/home/myst/projects/mulesoft-loop-engineering")
SCRIPTS = REPO / "scripts"


def casual_yaml(hours=1, deploy="denied"):
    """カジュアルモードの印 (期限つき)。hours<0 で期限切れの印になる。"""
    import datetime
    when = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=hours)
    return f"expires: {when.strftime('%Y-%m-%dT%H:%M:%SZ')}\ndeploy: {deploy}\n"


def mk_project(tmp, *, tasks=None, claude=None, auth=None, sandbox=None, files=None, git=True):
    """利用者プロジェクトに見える最小のディレクトリを作る。"""
    p = pathlib.Path(tmp)
    if tasks is not None:
        (p / "tasks").mkdir(parents=True, exist_ok=True)
        for name, body in tasks.items():
            (p / "tasks" / name).write_text(body)
    if claude is not None:
        (p / "CLAUDE.md").write_text(claude)
    if auth is not None:
        (p / "context/deployment").mkdir(parents=True, exist_ok=True)
        (p / "context/deployment/authorizations.yaml").write_text(auth)
    if sandbox is not None:
        (p / "context/deployment").mkdir(parents=True, exist_ok=True)
        (p / "context/deployment/sandbox.yaml").write_text(sandbox)
    for name, body in (files or {}).items():
        f = p / name
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(body)
    if git:
        subprocess.run(["git", "init", "-q"], cwd=p, check=False)
    return p


def run(script, stdin, cwd, env=None):
    e = dict(os.environ)
    e.update(env or {})
    cmd = [sys.executable, str(script)]
    r = subprocess.run(cmd, input=stdin, cwd=str(cwd), env=e,
                       capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout, r.stderr


def cases_for(name, tmpdir):
    """(ケース名, stdin, cwd を作る関数, env) を返す。"""
    t = lambda n: os.path.join(tmpdir, n)

    if name == "loop-reminder":
        return [
            ("tasks 無し", "", lambda d: mk_project(d), {}),
            ("todo 2 / blocked 1", "", lambda d: mk_project(d, tasks={
                "T-001.md": "---\nstatus: todo\n---\n", "T-002.md": "---\nstatus: failed\n---\n",
                "T-003.md": "---\nstatus: blocked\n---\n", "T-004.md": "---\nstatus: passed\n---\n"}), {}),
        ]

    if name == "quick-check":
        xml_ok = '<?xml version="1.0"?><mule xmlns="http://www.mulesoft.org/schema/mule/core"><flow name="a"/></mule>'
        xml_broken = '<?xml version="1.0"?><mule><flow name="a">'
        xml_db = ('<?xml version="1.0"?><mule xmlns="http://www.mulesoft.org/schema/mule/core" '
                  'xmlns:db="http://www.mulesoft.org/schema/mule/db"><flow name="a">'
                  '<db:select config-ref="c"><db:sql>SELECT 1</db:sql></db:select></flow></mule>')
        def mkxml(d, body, kind="api", layer="process"):
            return mk_project(d, claude=f"kind: {kind}\nlayer: {layer}\n",
                              files={"src/main/mule/x.xml": body})
        return [
            ("file_path 無し", json.dumps({"tool_input": {}}), lambda d: mk_project(d), {}),
            ("存在しないファイル", json.dumps({"tool_input": {"file_path": t("nope.xml")}}), lambda d: mk_project(d), {}),
            ("正しい Mule XML (process 層)", None, lambda d: mkxml(d, xml_ok), {}),
            ("壊れた XML", None, lambda d: mkxml(d, xml_broken), {}),
            ("process 層で db コネクタ", None, lambda d: mkxml(d, xml_db), {}),
            ("system 層で db コネクタ", None, lambda d: mkxml(d, xml_db, layer="system"), {}),
            ("batch では層を見ない", None, lambda d: mkxml(d, xml_db, kind="batch", layer="process"), {}),
            ("done_when のあるゴール", None, lambda d: mk_project(d, tasks={"T-001.md": "---\ndone_when: bash x.sh\n---\n"}), {}, "tasks/T-001.md"),
            ("done_when の無いゴール", None, lambda d: mk_project(d, tasks={"T-001.md": "---\nstatus: todo\n---\n"}), {}, "tasks/T-001.md"),
        ]

    if name == "secret-guard":
        secret = "s3cr3t-value-aaaaaaaaaaaa"
        return [
            ("tool_input 無し", json.dumps({}), lambda d: mk_project(d), {}),
            ("秘密を含まない Write", json.dumps({"tool_input": {"file_path": "a.md", "content": "hello"}}),
             lambda d: mk_project(d), {"ANYPOINT_CLIENT_SECRET": secret}),
            ("秘密を含む Write", json.dumps({"tool_input": {"file_path": "a.md", "content": f"pw={secret}\n"}}),
             lambda d: mk_project(d), {"ANYPOINT_CLIENT_SECRET": secret}),
            ("秘密を含む Edit (new_string)", json.dumps({"tool_input": {"file_path": "a.md", "new_string": secret}}),
             lambda d: mk_project(d), {"ANYPOINT_CLIENT_SECRET": secret}),
            ("環境変数が短い (8 文字未満)", json.dumps({"tool_input": {"file_path": "a.md", "content": "pw=short"}}),
             lambda d: mk_project(d), {"ANYPOINT_CLIENT_SECRET": "short"}),
            ("壊れた JSON", "{not json", lambda d: mk_project(d), {}),
            # **カジュアルでも git に入るファイルには書かせない。** 無視されるファイルには書かせる。
            ("カジュアル + 追跡ファイル",
             json.dumps({"tool_input": {"file_path": "tracked.md", "content": f"pw={secret}"}}),
             lambda d: mk_project(d, files={"tracked.md": "x", "context/casual.yaml": casual_yaml(),
                                            ".gitignore": "ignored.local\n"}),
             {"ANYPOINT_CLIENT_SECRET": secret}),
            ("カジュアル + git が無視するファイル",
             json.dumps({"tool_input": {"file_path": "ignored.local", "content": f"pw={secret}"}}),
             lambda d: mk_project(d, files={"ignored.local": "x", "context/casual.yaml": casual_yaml(),
                                            ".gitignore": "ignored.local\n"}),
             {"ANYPOINT_CLIENT_SECRET": secret}),
        ]

    if name == "stop-guard":
        def transcript(d, text):
            p = pathlib.Path(d) / "t.jsonl"
            p.write_text(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}) + "\n")
            return str(p)
        def mkcasual(proj):
            (proj / "context").mkdir(parents=True, exist_ok=True)
            (proj / "context/casual.yaml").write_text(casual_yaml())
            return proj

        def mk(d, text, status="passed", with_gs=True):
            proj = mk_project(d, tasks={"T-001.md": f"---\nstatus: {status}\ndone_when: true\n---\n"})
            if with_gs:
                (proj / "scripts").mkdir(exist_ok=True)
                shutil.copy(REPO / "template/scripts/goal-state.sh", proj / "scripts/goal-state.sh")
            transcript(proj, text)
            return proj
        return [
            ("tasks 無し", json.dumps({"stop_hook_active": False, "transcript_path": "/nope"}),
             lambda d: mk_project(d), {}),
            ("stop_hook_active true", json.dumps({"stop_hook_active": True, "transcript_path": "/nope"}),
             lambda d: mk(d, "## 次にすること"), {}),
            ("3 ブロックで締めている", None, lambda d: mk(d, "## 現在地\nx\n## 次にすること\ny\n## そのあと\nz"), {}),
            # **太字で締めた応答を差し戻さない。** 記法を強制していた版は、正しく締めた応答を
            # 差し戻して同じ報告を 2 回並べた (実測: /mule-init 直後)。
            ("太字で締めている", None,
             lambda d: mk(d, "**現在地**\nx\n\n**次にすること**\ny\n\n**そのあと**\nz"), {}),
            ("締めていない", None, lambda d: mk(d, "おわりました"), {}),
            ("進められるゴールがある", None, lambda d: mk(d, "## 次にすること", status="todo"), {}),
            ("カジュアル (締め方を強制しない)", None,
             lambda d: mkcasual(mk(d, "おわりました", status="todo")), {}),
        ]

    if name == "promote-guard":
        def mk(d, broken):
            proj = pathlib.Path(d) / "ml"
            shutil.copytree(REPO, proj, ignore=shutil.ignore_patterns(".git", "target"))
            # **写しの中では、このテスト自身を空実装にする。** promote-guard は PR の前に
            # hooks-check.py も走らせるので、そのままだと「テスト → promote-guard → テスト → ...」と
            # 際限なく増える (実測: 止めるまで戻ってこなかった)。**消すのではなく空にする** —
            # 消すと checks-audit が「表にあるのに実体が無い」と正しく落ち、今度はそれで deny になる
            # (実測)。ここで見たいのは索引・fixtures・表の検査が PR を止めるかどうか。
            (proj / "scripts/hooks-check.py").write_text("import sys\nsys.exit(0)\n")
            if broken:
                # **索引の件数を直書きして壊さない。** 件数は項目を足すたびに変わるので、
                # 数字を書くとテストが黙って牙を失う (実測: 7 → 9 にした版で deny しなくなった)。
                # 代わりに「索引に載っていない gotchas ファイル」を 1 つ置く — これは
                # knowledge-index-check が版に関係なく必ず捕まえる壊し方。
                (proj / "knowledge/gotchas/zz-not-in-index.md").write_text("## 索引に載せていない項目\n")
            subprocess.run(["git", "init", "-q"], cwd=proj, check=False)
            return proj
        return [
            ("PR でないコマンド", json.dumps({"tool_input": {"command": "ls"}, "cwd": "/tmp"}),
             lambda d: mk_project(d), {}),
            ("検査が通る状態で gh pr create", None, lambda d: mk(d, False), {}),
            ("索引がずれた状態で gh pr create", None, lambda d: mk(d, True), {}),
            ("利用者プロジェクト (検査スクリプト無し)", json.dumps({"tool_input": {"command": "gh pr create"}, "cwd": "/tmp"}),
             lambda d: mk_project(d), {}),
        ]

    if name == "deploy-guard":
        A_OK = "deploy:\n  sandbox: allowed\n  production: denied\n"
        A_NG = "deploy:\n  sandbox: denied\n  production: denied\n"
        S = "kind: cloudhub2\nenvironment: Sandbox\ntarget: rootps\n"
        S_PROD = "kind: cloudhub2\nenvironment: Production\ntarget: rootps\n"
        POM = "<project><groupId>g</groupId><artifactId>a</artifactId></project>"
        def mk(d, auth, sandbox):
            return mk_project(d, auth=auth, sandbox=sandbox, files={"pom.xml": POM})
        return [
            ("デプロイでないコマンド", json.dumps({"tool_input": {"command": "ls"}}), lambda d: mk(d, A_OK, S), {}),
            ("許可あり Sandbox", None, lambda d: mk(d, A_OK, S), {}),
            ("許可なし", None, lambda d: mk(d, A_NG, S), {}),
            ("本番の環境名", None, lambda d: mk(d, A_OK, S_PROD), {}),
            ("authorizations.yaml が無い", json.dumps({"tool_input": {"command": "mvn deploy -DmuleDeploy"}}),
             lambda d: mk_project(d), {}),
            # **カジュアル + --deploy は許可ファイルの代わりになるが、本番は緩めない。期限切れも効かない。**
            ("カジュアル --deploy + Sandbox", None,
             lambda d: mk_project(d, sandbox=S, files={"pom.xml": POM, "context/casual.yaml": casual_yaml(deploy="allowed")}), {}),
            ("カジュアル --deploy + 本番の環境名", None,
             lambda d: mk_project(d, sandbox=S_PROD, files={"pom.xml": POM, "context/casual.yaml": casual_yaml(deploy="allowed")}), {}),
            ("カジュアルの期限切れ", None,
             lambda d: mk_project(d, auth=A_NG, sandbox=S, files={"pom.xml": POM,
                 "context/casual.yaml": "expires: 2020-01-01T00:00:00Z\ndeploy: allowed\n"}), {}),
        ]

    if name == "outside-read-guard":
        # **外の pom.xml を読むのを止める。** 中の pom.xml と、外でも対象外のファイルは通す。
        # 隣のプロジェクトは tmpdir の中に作るが、**プロジェクトの git ルートの外**に置く。
        # **プロジェクトは d/proj に作る。** d 自体をプロジェクトにすると隣が git ルートの中に
        # 入ってしまい、「外」を試したことにならない (最初そう書いて素通りした)。
        def outside(d, fname="pom.xml", body="<project><groupId>OTHER</groupId></project>"):
            proj = mk_project(os.path.join(d, "proj"), tasks={"T-001.md": "---\nstatus: todo\n---\n"})
            nb = os.path.join(d, "neighbor")
            os.makedirs(nb, exist_ok=True)
            with open(os.path.join(nb, fname), "w") as f:
                f.write(body)
            return proj

        return [
            ("外のプロジェクトの pom.xml", None, outside, {}, "../neighbor/pom.xml"),
            ("外の無関係なファイル", None, lambda d: outside(d, "NOTES.md", "ただの文書"), {},
             "../neighbor/NOTES.md"),
            ("中のプロジェクトの pom.xml", None,
             lambda d: mk_project(os.path.join(d, "proj"),
                                  tasks={"T-001.md": "---\nstatus: todo\n---\n"},
                                  files={"pom.xml": "<project/>"}), {}, "pom.xml"),
        ]

    if name == "wave-guard":
        return [
            ("wave-owned 無し", json.dumps({"tool_input": {"file_path": "a.xml"}}), lambda d: mk_project(d), {}),
            ("他ゴールが宣言したファイル", json.dumps({"tool_input": {"file_path": "pom.xml"}}),
             lambda d: mk_project(d, files={".claude/wave-owned": "pom.xml T-002\n", "pom.xml": "<x/>"}), {}),
            ("自分が宣言したファイル", json.dumps({"tool_input": {"file_path": "src/main/mule/a.xml"}}),
             lambda d: mk_project(d, files={".claude/wave-owned": "pom.xml T-002\n", "src/main/mule/a.xml": "<x/>"}), {}),
        ]
    raise SystemExit(f"未知の hook: {name}")


# 期待値。**v0.6.44 で bash 版と 34 ケース突き合わせて一致したもの**をそのまま残している。
# 見るのは (終了コード, 何を出したか) だけ。"deny"/"allow" は hook が返す JSON、"err" は差し戻し、
# "out" は標準出力、"無音" は何もしないこと。**文面は見ない** (文面を変えるたびに直すのは本末転倒)。
EXPECTED = {
    ("loop-reminder", "tasks 無し"): (0, "無音"),
    ("loop-reminder", "todo 2 / blocked 1"): (0, "out"),
    ("quick-check", "file_path 無し"): (0, "無音"),
    ("quick-check", "存在しないファイル"): (0, "無音"),
    ("quick-check", "正しい Mule XML (process 層)"): (0, "無音"),
    ("quick-check", "壊れた XML"): (2, "err"),
    ("quick-check", "process 層で db コネクタ"): (2, "err"),
    ("quick-check", "system 層で db コネクタ"): (0, "無音"),
    ("quick-check", "batch では層を見ない"): (0, "無音"),
    ("quick-check", "done_when のあるゴール"): (0, "無音"),
    ("quick-check", "done_when の無いゴール"): (2, "err"),
    ("secret-guard", "tool_input 無し"): (0, "無音"),
    ("secret-guard", "秘密を含まない Write"): (0, "無音"),
    ("secret-guard", "秘密を含む Write"): (0, "deny"),
    ("secret-guard", "秘密を含む Edit (new_string)"): (0, "deny"),
    ("secret-guard", "環境変数が短い (8 文字未満)"): (0, "無音"),
    ("secret-guard", "壊れた JSON"): (0, "無音"),
    # カジュアルモード: 緩めてよいものと、緩めてはいけないもの (v0.6.47)
    ("secret-guard", "カジュアル + 追跡ファイル"): (0, "deny"),
    ("secret-guard", "カジュアル + git が無視するファイル"): (0, "err"),
    ("stop-guard", "カジュアル (締め方を強制しない)"): (0, "無音"),
    ("deploy-guard", "カジュアル --deploy + Sandbox"): (0, "allow"),
    ("deploy-guard", "カジュアル --deploy + 本番の環境名"): (0, "deny"),
    ("deploy-guard", "カジュアルの期限切れ"): (0, "deny"),
    ("stop-guard", "tasks 無し"): (0, "無音"),
    ("stop-guard", "stop_hook_active true"): (0, "無音"),
    ("stop-guard", "3 ブロックで締めている"): (0, "無音"),
    ("stop-guard", "太字で締めている"): (0, "無音"),
    ("stop-guard", "締めていない"): (2, "err"),
    ("stop-guard", "進められるゴールがある"): (2, "err"),
    ("promote-guard", "PR でないコマンド"): (0, "無音"),
    ("promote-guard", "検査が通る状態で gh pr create"): (0, "無音"),
    ("promote-guard", "索引がずれた状態で gh pr create"): (0, "deny"),
    ("promote-guard", "利用者プロジェクト (検査スクリプト無し)"): (0, "無音"),
    ("deploy-guard", "デプロイでないコマンド"): (0, "無音"),
    ("deploy-guard", "許可あり Sandbox"): (0, "allow"),
    ("deploy-guard", "許可なし"): (0, "deny"),
    ("deploy-guard", "本番の環境名"): (0, "deny"),
    ("deploy-guard", "authorizations.yaml が無い"): (0, "無音"),
    ("outside-read-guard", "外のプロジェクトの pom.xml"): (0, "deny"),
    ("outside-read-guard", "外の無関係なファイル"): (0, "無音"),
    ("outside-read-guard", "中のプロジェクトの pom.xml"): (0, "無音"),
    ("wave-guard", "wave-owned 無し"): (0, "無音"),
    ("wave-guard", "他ゴールが宣言したファイル"): (0, "deny"),
    ("wave-guard", "自分が宣言したファイル"): (0, "無音"),
}


def check(name, tmproot):
    py = SCRIPTS / f"{name}.py"
    if not py.is_file():
        print(f"  {name}: {py} が無い")
        return False
    ok = True
    for case in cases_for(name, tmproot):
        label, stdin, mk, env = case[:4]
        rel_target = case[4] if len(case) > 4 else None
        d = tempfile.mkdtemp(dir=tmproot)
        cwd = mk(d)
        s = stdin
        if s is None:      # cwd が決まってから作る必要がある入力
            s = (json.dumps({"tool_input": {"file_path": str(pathlib.Path(cwd) / rel_target)}})
                 if rel_target else default_stdin(name, cwd))
        rc, out, err = run(py, s, cwd, env)
        got = (rc, digest(out, err))
        want = EXPECTED.get((name, label))
        if want is None:
            print(f"  [?  ] {label}: 期待値が EXPECTED に無い → got={got}")
            ok = False
            continue
        good = got == want
        print(f"  [{'OK ' if good else 'NG '}] {label}: {got}" + ("" if good else f"  ← 期待 {want}"))
        if not good:
            ok = False
            print(f"       out={out[:200]!r}")
            print(f"       err={err[:300]!r}")
    return ok


def digest(out, err):
    """何が起きたかを 1 語で。**無音のまま「通った」と言わないため。**"""
    if '"deny"' in out:
        return "deny"
    if '"allow"' in out:
        return "allow"
    if out.strip():
        return "out"
    if err.strip():
        return "err"
    return "無音"


def norm(s):
    """一時ディレクトリ名など、実行ごとに変わる文字列を消す。"""
    import re
    return re.sub(r"/tmp/[^\s\"']+", "<tmp>", s)


def default_stdin(name, cwd):
    if name == "quick-check":
        return json.dumps({"tool_input": {"file_path": str(pathlib.Path(cwd) / "src/main/mule/x.xml")}})
    if name == "stop-guard":
        return json.dumps({"stop_hook_active": False, "transcript_path": str(pathlib.Path(cwd) / "t.jsonl")})
    if name == "promote-guard":
        return json.dumps({"tool_input": {"command": f"cd {cwd} && gh pr create --title x --body y"}, "cwd": str(cwd)})
    if name == "deploy-guard":
        return json.dumps({"tool_input": {"command": "mvn deploy -DmuleDeploy"}, "cwd": str(cwd)})
    return "{}"


if __name__ == "__main__":
    names = sys.argv[1:]
    if not names or names == ["--all"]:
        names = ["loop-reminder", "quick-check", "secret-guard", "stop-guard", "promote-guard",
             "deploy-guard", "wave-guard", "outside-read-guard"]
    root = tempfile.mkdtemp(prefix="hookcmp-")
    bad = []
    for n in names:
        print(f"== {n}")
        if not check(n, root):
            bad.append(n)
    print()
    print("hooks-check: 全 hook が期待どおり" if not bad else f"hooks-check: 期待と違う: {', '.join(bad)}")
    sys.exit(1 if bad else 0)
