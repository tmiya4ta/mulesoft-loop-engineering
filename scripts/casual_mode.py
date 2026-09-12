#!/usr/bin/env python3
"""カジュアルモードが効いているかを hook が読むための共通の判定。

**何のためか。** ちょっと試したいだけのときに、台帳・TDD・許可ファイル・3 ブロックの締めまで
全部求められると、作るより手続きの方が長くなる。そこで**明示的に、期限つきで**緩める口を作る。

**緩めるもの** (`context/casual.yaml` があり、期限内のとき):
  - 台帳 (tasks/T-*.md) と TDD の強制 … 手順書の側で外す
  - 3 ブロックの締めと「まだ進められる」の差し戻し (stop-guard)
  - 層の越境の検査 (quick-check) … 構文の検査は残す
  - **git が無視するファイルへの秘密の書き込み** (secret-guard) … 追跡ファイルへは通さない
  - `deploy: allowed` を書けば Sandbox へのデプロイに authorizations.yaml を要求しない

**緩めないもの** (カジュアルでも常に効く。ここが緩むと取り返しがつかないため):
  - **本番系の環境名へのデプロイ** — 常に deny
  - **publish 前の jar の混入検査** — Exchange に上げたら組織の全員から見える
  - **追跡されているファイルへの秘密の書き込み** — git に入ると履歴から消せない
  - 秘密の**値そのもの**を hook の出力に書かないこと

期限を必須にしているのは、**切り忘れた緩みは誰にも見えない**から。既定は 8 時間で、
過ぎたら自動的に通常モードに戻る (ファイルは残っていても効かない)。
"""
import datetime, os, re


def _find(start):
    """cwd から git ルートまで遡って context/casual.yaml を探す (deploy-guard と同じ形)。"""
    d = start
    while d:
        p = os.path.join(d, "context/casual.yaml")
        if os.path.isfile(p):
            return p
        if os.path.exists(os.path.join(d, ".git")):
            return ""
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent
    return ""


def casual(cwd=None):
    """効いていれば設定の dict、効いていなければ None。期限切れは None。"""
    p = _find(cwd or os.getcwd())
    if not p:
        return None
    try:
        text = open(p, encoding="utf-8", errors="ignore").read()
    except Exception:
        return None
    cfg = {"_path": p}
    for line in text.splitlines():
        m = re.match(r"^([a-z_]+):\s*([^#]*)", line)
        if m:
            cfg[m.group(1)] = m.group(2).strip().strip('"')
    exp = cfg.get("expires", "")
    if not exp:
        return None                      # 期限の無いカジュアルモードは認めない
    try:
        when = datetime.datetime.fromisoformat(exp.replace("Z", "+00:00"))
        if when.tzinfo is None:
            when = when.replace(tzinfo=datetime.timezone.utc)
    except Exception:
        return None
    if when < datetime.datetime.now(datetime.timezone.utc):
        return None                      # 切れている
    return cfg


def git_ignored(path, cwd=None):
    """そのパスを git が無視しているか (= コミットに入らないか)。判定できなければ False。"""
    import subprocess
    try:
        r = subprocess.run(["git", "check-ignore", "-q", path], cwd=cwd or os.getcwd(),
                           capture_output=True, timeout=10)
        return r.returncode == 0
    except Exception:
        return False
