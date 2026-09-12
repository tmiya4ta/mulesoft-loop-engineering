# mulesoft-loop-engineering

**Build MuleSoft APIs with Claude Code, through a loop instead of a chat.**

[English](README.md) · [日本語](README.ja.md)

This repository is the Claude Code plugin **`mule-loop`** and its project template. You
describe what the API should do; it carries that from specification → acceptance criteria →
a goal ledger → implementation → pull request, in one console. **You do not need to know
MuleSoft to start** — `/mule-start` asks what it needs to know.

Implementation is TDD throughout (Red → Green → Refactor). The reasoning behind the design is
in [docs/methodology.md](docs/methodology.md).

> **v0.6.7** — see [Release notes](#release-notes).

---

## Install

```bash
# 1. Register this repo as a marketplace, then install the plugin
claude plugin marketplace add tmiya4ta/mulesoft-loop-engineering
claude plugin install mule-loop@mule-loop-marketplace

# 2. Pull in dependencies (mattpocock-skills, MuleSoft official skills, MCP preflight)
claude
> /mule-setup
```

From a local checkout instead: `claude plugin marketplace add /path/to/mulesoft-loop-engineering`

To try it without registering anything:

```bash
claude --plugin-dir /path/to/mulesoft-loop-engineering
```

---

## Use it

```bash
cd my-order-sapi           # a Mule project, new or existing
claude
> /mule-init               # lay down the skeleton + context/, tasks/, budget.yaml (once)
#   → now put your material in context/requirements/ (URLs are fine)
> /mule-start an API that returns order status
```

From there you answer questions. That is the whole interface.

### Stopping earlier or later

| Command | How far it goes |
|---|---|
| `/mule-start --spec-only` | Spec and acceptance criteria, up to your approval |
| `/mule-start --plan-only` | Through cutting the ledger (`tasks/T-*.md`) |
| `/mule-start` | Implementation, review, and a PR (**you** merge) |
| `/mule-run` | Only the unfinished goals in the ledger — this is how you resume |
| `/mule-run T-003` | One goal |
| `/mule-run --parallel 1` | Force serial. Parallel is the default; `--parallel` only turns it **down** |
| `/mule-setup` | Install external skills and MCP prerequisites (first run) |
| `/mule-tdd` | The Red → Green → Refactor discipline executors follow. Usable by hand too |
| `/mule-deploy` | After merge: deploy to Sandbox, verify with `samples/`, feed failures back to learning |
| `/mule-learn` | Promote a failure seen twice into a hook or rule. `--share` publishes it to everyone |
| `/mule-status` | **Lost? Run this.** Says where you are and the single next thing to do |

---

## You decide in five places

Everything else proceeds on its own and is shown to you as a list of stated assumptions at
approval time.

| # | Decision |
|---|---|
| **0** | At the start, `/mule-start` asks for the blanks in `context/decisions.yaml` — **all at once, one time**. Fill it in beforehand and you are not asked at all. After this, no questions until approval |
| **1** | "Yes" to the plain-language behaviour `/mule-start` reads back to you |
| **2** | Merging the PR |
| **3** | Production deployment (Sandbox is handled by `/mule-deploy` without asking, given `allowed` in `authorizations.yaml`; `deploy-guard.sh` decides in a hook) |
| **4** | Merging the promotion PR from `/mule-learn` |

---

## Before you start

1. Put your material in `context/requirements/` — or list URLs in `context/sources.yaml`.
   > [!IMPORTANT]
   > **`/mule-start` will not begin while this is empty.**
2. Put Mule version and connection material in `context/environment/`. Leave it empty if you
   don't know — it will be researched and recorded with sources.
3. Check the ceilings in `budget.yaml`.
4. **Only if you want Sandbox deployment:** set `deploy.sandbox` to `allowed` in
   `context/deployment/authorizations.yaml`, and write the destination (cloudhub2 / rtf,
   target) in `context/deployment/sandbox.yaml`.

---

## Cost control

| Mechanism | What it does |
|---|---|
| `budget.yaml` | Ceilings on executor launches and elapsed time. **Over the line, nothing more is dispatched** |
| Automatic parallel throttle | Forced down to 1 below 25% remaining budget |
| Model tiering | `sonnet` for implementation; `opus` only on the third attempt |
| `scripts/cost-report.sh` | Real per-model cost for the session, in USD |
| `scripts/metrics.sh` | Loop wall-clock, first-pass rate, rework, coverage |

> [!NOTE]
> Stopping is granular **to the next dispatch**. An executor already running cannot be
> interrupted mid-goal.

---

## What's inside

```
.claude-plugin/   plugin.json / marketplace.json
skills/
  mule-setup/     Install external dependencies (scripts/setup-deps.sh)
  mule-init/      Lay down the template
  mule-tdd/       The TDD discipline (executors always follow it)
  mule-munit/     MUnit traps in the order you hit them (the ledger's biggest cluster, 17/62)
  mule-deploy/    Deploy loop — Sandbox, verify with samples, failures back to learning
  mule-learn/     Learning loop — count failures, promote, share
  mule-status/    Navigation: where you are, what's next (a report for people)
  mule-guide/     The step-by-step guide: next action and copyable command per situation (for agents)
  mule-policy/    Find / inspect / apply / remove API Manager policies, with a table of the common ones
  platform-assistant/  MuleSoft's official meta-skill, vendored (Apache-2.0)
  mule-start/     Intent → plan → execute, end to end
  mule-run/       Plan and execute loops only (for resuming)
agents/
  mule-executor.md  Drives one goal until done_when passes (worktree-isolated)
  mule-reviewer.md  Read-only review
hooks/hooks.json  Launched via scripts/run-hook.sh (finds python3 / python / py -3 and hands over)
                  Before a deploy: scripts/deploy-guard.py (reads authorizations.yaml, answers allow/deny)
                  Before a write:  scripts/secret-guard.py (denies a secret's own value entering a file)
                  Before a PR:     scripts/promote-guard.py (denies gh pr create until the index, fixtures and check table pass)
                  Before an edit:  scripts/wave-guard.py (keeps the dispatcher off files it assigned to a goal)
                  On every edit: scripts/quick-check.py (seconds-long validation)
                              └ scripts/mule-xml-shape.sh (shapes that fail XSD; ledger fingerprints only)
                  Every turn:    scripts/loop-reminder.py (re-inject the discipline)
                  End of reply:  scripts/stop-guard.py (bounce once if not closed in 3 blocks,
                                 or if a goal can still advance per goal-state.sh)
scripts/hooks-check.py  Automated test: do the 7 hooks return the decided verdict for the decided input (34 cases)
knowledge/fixtures/  Minimal inputs proving each hook actually denies (bash scripts/fixtures-check.sh)
knowledge/mule-basics.md  Index over basics/; executors read the index, then the one topic they touch
knowledge/basics/*.md  Mule basics distilled from two loops and the user's skill, one file per topic (10)
knowledge/gotchas.md  Index over gotchas/: pick a topic by symptom
knowledge/gotchas/*.md  Measured traps with evidence, one file per topic (9)
template/reference/   Reference skeleton (global.xml / impl / MUnit / dwl / config) taken from an API that passed
template/         What /mule-init distributes:
  context/        Where premises live (requirements / environment / deployment) + sources.yaml
  budget.yaml     Cost ceilings, checked before /mule-run dispatches
  context/deployment/authorizations.yaml   Deploy + live-system permissions (written by a human)
  tasks/          The goal ledger (done_when + attempt log)
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh, preflight.sh,
                  munit-coverage-mode.sh, run-log.sh, metrics.sh, cost-report.sh,
                  schema-index.sh (extracts connector definitions + XSDs from jars in ~/.m2),
                  plugin-root.sh (resolves the plugin and skills to paths),
                  k-new.sh (a machine picks the K filename),
                  teeth-check.sh (a machine measures whether a test has teeth),
                  spec-check.sh (RAML/sample/implementation drift a machine can catch),
                  jar-leak-check.sh (does the jar being shipped contain git-ignored files?),
                  goal-state.sh (exit code says whether any goal can still advance agent-side),
                  gotcha-lookup.sh (look up known traps from an error's raw text),
                  deploy-precheck.sh (gather everything to ask before a deploy into one round),
                  portal-search.py (from a field name, find the Platform API operation that returns it),
                  anypoint-api.py (GET-only Platform API caller; fills {org} {env}, --find searches the response),
                  gateway-public-url.py (the outside URL of an API deployed to a Flex Gateway),
                  env-probe.py (lists environments, deploy targets and Flex Gateways, and the sandbox.yaml block to fill),
                  app-status.py (is the deployed app RUNNING? the deploy goal's done_when when ingress: gateway),
                  policy.py (find / config / list / apply / remove policies; writes need the authorizations.yaml grant)
.mcp.json         MuleSoft DX MCP Server (stdio) + Platform MCP Server (http)
docs/methodology.md  The method, the 4 validator tiers, **the ordered check list (20, numbered)**
docs/mulesoft-tools.md
```

The discipline lives in **hooks**, not in the prompt — so it does not fade over a long
conversation.

---

## MuleSoft official tools

[docs/mulesoft-tools.md](docs/mulesoft-tools.md) lists the DX MCP Server (21 tools), the
Platform MCP Server (68 tools) and the official `mulesoft-dx` skills, with where each fits in
the loop. MCP is enabled by `.mcp.json`. The DX MCP Server needs Connected App credentials in
the environment:

```bash
export ANYPOINT_CLIENT_ID=...
export ANYPOINT_CLIENT_SECRET=...
export ANYPOINT_REGION=PROD_JP
```

---

## Required tools

| Tool | What breaks without it |
|---|---|
| Maven + Mule Maven Plugin | Stage 2 and 3 validation does not run — **required** |
| Anypoint CLI v4 + `@salesforce/anypoint-cli-dx-mule-plugin` | `/mule-init` cannot scaffold. A hand-written pom fails to resolve libraries |
| `dw` CLI | DataWeave validation drops from seconds to stage 2 |
| `xmllint` | Immediate Mule XML checking is skipped |
| `gh` | PR creation becomes manual |
| MuleSoft Enterprise Maven credentials | MUnit **coverage percentage** does not work (an EE-only feature). `scripts/coverage-check.sh` then guarantees only that every flow is reached — branches inside a flow stay invisible |

### Per-OS prerequisites

The scripts assume **bash + python3 + jq + curl + git** only (no Node). `bash scripts/preflight.sh` checks those
four before a wave and stops, naming what is missing.

| OS | Prerequisites |
|---|---|
| Linux | Works as is (development and testing happen here) |
| macOS | bash 3.2 and BSD sed are the defaults. **`sed -i` and GNU-only extensions are not used** (two were fixed in v0.6.43). `jq` via `brew install jq` |
| Windows | **Git for Windows is required.** Claude Code uses the Bash tool only when Git Bash is present; without it it falls back to PowerShell and `.sh` hooks do not run ([setup](https://code.claude.com/docs/en/setup)). `jq` and `python3` are not in Git Bash — install them separately (`winget install jqlang.jq` / Python). Dependencies on `unzip` and `timeout` were removed (v0.6.43) |

**Windows and macOS have not been exercised on real machines.** What is guaranteed today is that `preflight.sh`
names the missing prerequisite. If something does not work, PR it to the plugin via `/mule-learn`.

---

## Release notes

<details>
<summary><b>v0.6.46</b> — Two findings from actually closing the bypass. **A 401 is not evidence that the route is right**</summary>

v0.6.45's `ingress: gateway` was carried out for real in the user's Sandbox (measuring `ch2-public-url.py --remove`).
Doing so revealed that **the gateway route had never worked end to end**.

| Found | What |
|---|---|
| **The upstream needs a trailing slash** | The gateway strips the listen path (`/inventory3-api/`) and **concatenates the remainder** (`inventory`, no leading slash) onto the upstream URI. `https://app/api` becomes `https://app/apiinventory` → `404 No listener for endpoint: /apiinventory`. With `/api/` it returned 200 with real inventory |
| **Apply/unapply take seconds to reach the gateway** | Right after a 201 / 204 the gateway still answers with **the previous state** (first call after removal was still 401, the second returned 200; after re-applying, the first was 200 and the second 401) |

**Why it was invisible.** Without a contract, client-id-enforcement answers 401 *before* the upstream is called.
So **"401 without auth" was being read as "the route works"** while the upstream was broken. The only way to see
it is to remove the policy briefly, confirm a 200 straight through, and re-apply the same configuration at once.

**`policy-check.sh` now waits for the answer to settle** (until the same result repeats, up to 5 rounds, 8s apart).
Judging on a single call right after applying confuses "not effective" with "still protected".

`/mule-deploy` documents **the order for switching something already running as `public` over to `gateway`**:
repoint the upstream to the internal URL (with the trailing slash) first, and remove the public URL *after*.
The other order severs the route.

Live result (the user's Sandbox, 2026-09-12): upstream repointed to the internal URL → policy briefly removed and
a straight-through 200 confirmed → same configuration re-applied and 401 restored → `--remove` deleted the public
URL → **direct access 404, through the gateway 401, app RUNNING**. The bypass is closed.

</details>

<details>
<summary><b>v0.6.45</b> — **Always ask whether to attach a public endpoint** before deploying (`ingress`). The environment is read by machine, up front</summary>

The "401 through the gateway, but 200 without auth on the app's own public URL" found in inventory3-api came
from **the procedure attaching a public endpoint by default**. Putting a gateway in front afterwards does not
help: the app URL stays alive, so the gateway can be bypassed. **The mistake was never offering the choice**,
so now there is one.

**`sandbox.yaml` gained `ingress`.** It defaults to `unknown`, and **deployment does not proceed while it is.**

| `ingress` | What happens | When |
|---|---|---|
| `public` | The app gets a public URL you can call directly | Quick to run. Nothing to protect with policies |
| `gateway` | The app gets **no** public URL; only through a Flex Gateway | Policies must bite. **Only this one has no bypass** |

`deploy-precheck.sh` rejects the undecided state, and lists the gateway name as a question when
`ingress: gateway` has an empty `gateway:`.

**`scripts/env-probe.py` (new) — "do we even have a Flex Gateway?" is now read by machine.**
Three GETs list the environments (including which is production), the deploy targets (shared space /
private space / RTF, with the Mule versions each supports) and that environment's Flex Gateways
(managed / self-managed, running or not), then print **the `sandbox.yaml` block to fill** and **the questions to
ask in one round**. With no gateway it says "only `public` is available today". `/mule-init` step 5d runs it, so
this is asked **at the start** instead of moments before a deploy (measured: not asking cost T-006 five rounds).

**The `ingress: gateway` path is wired end to end.**

| Added | Why |
|---|---|
| `ch2-public-url.py --remove` | Removes an existing public URL, re-reads to confirm it is gone, and says so when it is not |
| `app-status.py` (new) | With no public URL, **being unreachable from outside is correct**, so the deploy goal's `done_when` asks "is it RUNNING" instead (check 17b). Works without `anypoint-cli` |
| `smoke-check.py --no-basepath` | Do not append RAML's `/api` when hitting a gateway URL (the upstream already contains it, so appending gives `/api/api` and 404s everything) |

`/mule-deploy` branches steps 3 and 5 on `ingress`. `/mule-run` picks the deploy goal's `done_when` from
`ingress`, and refuses to dispatch while it is `unknown`.

</details>

<details>
<summary><b>v0.6.44</b> — Hooks and the API tools are now Python (no more jq). **The hooks finally have automated tests**</summary>

Prompted by "you're already using Python — why not do everything in Python?". Counting first: **41% was
already Python** (1890 lines of bash, 1323 lines of embedded Python), and `portal-search.sh` was 32 lines of
bash wrapping 271 lines of Python. All five bugs fixed in v0.6.43 came from **bash and GNU tools**.

The scope was agreed first: **the 7 hooks, the API tools, and getting rid of `jq`**. Scripts that only call
`mvn` or `git` (preflight, done, teeth-check…) stay in bash — rewriting them would only add `subprocess`
boilerplate, and the portability problems are not there.

**What this does not buy**: Python does **not** remove the need for Git Bash on Windows. The documented
procedures themselves are shell (`mvn ... | grep`, `&&`). What it buys is dropping the `jq` dependency and
the whole class of bash/GNU-tool breakage.

| Changed | What |
|---|---|
| 7 hooks | `deploy-guard` / `promote-guard` / `wave-guard` / `secret-guard` / `quick-check` / `loop-reminder` / `stop-guard` → `.py` |
| 6 API tools | `anypoint-api` / `portal-search` / `gateway-public-url` / `policy` / `ch2-public-url` / `smoke-check` → `.py` (jq and curl replaced by `json` and `urllib`) |
| `policy-check.sh` | Its last two jq calls became Python (the script itself stays bash) |
| `hooks.json` | Launches via `bash scripts/run-hook.sh <hook>.py` |

**`scripts/run-hook.sh` (new)**: 20 lines that only launch a hook, trying `python3` → `python` → `py -3`.
On Windows a python.org install often leaves `python3` unresolvable, and then **the hook dies with
"command not found" and every deny silently disappears** — the exact failure mode this repo exists to
prevent. If no python is found it prints one line to stderr and exits 0 (never blocks the work).

**`scripts/hooks-check.py` (new) — the hooks have automated tests for the first time.**
34 cases were built to prove the rewrite behaved identically, and **all 7 matched on (exit code, kind of
output)**. That comparison is now kept as the expectation, so editing a hook fails here. It runs from the
`/mule-learn --share` pre-PR chain and from `promote-guard` (row 22 of the table). `fixtures-check.sh` only
covered XML shapes — **the deny logic itself had no test**.

**Holes in the original bash, found by converting** (both fixed in the Python versions):

| Found | What was happening |
|---|---|
| `quick-check.sh` skipped everything for a **relative path** | `case */tasks/T-*.md` requires a leading `/`, so `tasks/T-001.md` bypassed both the done_when check and the layer-violation check (real hooks pass absolute paths, which is why it never showed) |
| `grep -P` in `smoke-check.sh` | GNU-only; macOS BSD grep has no `-P` |
| `smoke-check.sh` cut Japanese mid-character | `head -c 160` counts **bytes**, so `--dry-run` previews were mangled (Python counts characters) |

**Every equivalence was checked by machine.** 34 hook cases; `smoke-check`'s 46 `--dry-run` lines identical
(only the preview truncation improved) plus identical verdict lines, `deploy-log.jsonl` and exit code against
a local stub server; `anypoint-api` / `gateway-public-url` / `portal-search` / `ch2-public-url` matched the old
versions **against live Anypoint**, and `policy` was exercised with one apply/remove round trip in the user's
Sandbox (201 / 204, original state restored).

`preflight.sh` now compares `.py` as well as `.sh` (otherwise a renamed tool silently never reaches a
project). `__pycache__/` was added to `.gitignore`.

</details>

<details>
<summary><b>v0.6.43</b> — Five constructs that break on Windows / macOS, fixed (only looked after being asked)</summary>

Asked "does this actually work on Windows?", it turned out the README claimed "bash + python3 + jq" as the
premise **without ever having run it there**. With no machine to test on, the next best thing was done instead:
**a mechanical sweep of every external command the scripts call and every GNU-only construct.** Five were found.

| Fixed | What was happening |
|---|---|
| `jar-leak-check.sh` used `unzip` and **exited 0 when it was missing** | Git for Windows does not ship `unzip`. **The last check before publish was silently passing** in some environments. A jar is a zip, so it now reads it with python3's `zipfile` (as `schema-index.sh` does) and exits 2 when it cannot check |
| `bump-version.sh`'s `sed -i "0,/re/s//../"` | `-i` needs an argument on BSD sed (macOS) and the `0,/re/` address is GNU-only. **On macOS the version never bumped** — and Exchange refuses to overwrite the same version, so the deploy stalls there. Replaced with a python3 substitution |
| `fix-plugin-version.sh`'s `sed -i` | Same. Now goes through a temp file |
| `teeth-check.sh`'s `timeout 900 mvn ...` | On Windows the PATH picks up **a completely different `timeout.exe`** from System32 (which just waits N seconds). GNU `timeout` is now used only when present |
| `hooks.json` commands were bare `.sh` paths | Changed to `bash ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh`, matching the official docs' example (no dependence on the exec bit or shebang handling) |

**`preflight.sh` now checks the prerequisites.** If `python3` / `jq` / `curl` / `git` is missing it names it, prints
the per-OS install command and stops (measured with a PATH that had jq removed).

Every fix was exercised for real: `bump-version.sh` went 1.0.4 → 1.0.5 → 1.0.6 touching only the right element
(XML still valid), `fix-plugin-version.sh` rewrote 4.7.0 → 4.10.1, and `jar-leak-check.sh` produced **the same
listing as the old `unzip` version** for a purpose-built zip containing `META-INF/mule-src/`, rejecting a
git-ignored file with exit 2.

The README gained a per-OS prerequisites table and now states plainly that **Windows and macOS have not been
exercised on real machines** (Windows needs Git for Windows; without it Claude Code falls back to PowerShell and
`.sh` hooks do not run).

</details>

<details>
<summary><b>v0.6.42</b> — Finding, configuring, applying and removing policies is now a skill (`mule-policy`)</summary>

v0.6.41 made the gateway URL obtainable, but **a policy still cannot be written at all without knowing which
asset to apply and with what configuration.** The asset coordinates (groupId / assetId / version) and the
configuration keys were assumed to exist only in the UI, so the lookup itself became a tool.

**`skills/mule-policy/`** (new) — the order of operations is six lines. It carries a table of 13 common policies
(what you want → assetId → main configuration keys → caveats), which ones need a contract, automated policies,
and how to remove one.

**`scripts/policy.sh`** (new) — split by verb.

| | What it does |
|---|---|
| `find <word>` | Search Exchange for applicable policies (assetId + version). **131** are visible from this org |
| `config <assetId>` | Print the configuration keys, required flags and allowed values from the asset's `schema.json` |
| `list <instance>` | What is applied now (policyId / version / order / configuration) |
| `apply <instance> <assetId> [<version>] --config '<JSON>'` | Apply. Version defaults to latest. **Needs `policy.sandbox: allowed` in `authorizations.yaml`** |
| `remove <instance> <policyId>` | Unapply |

`apply` and `remove` are writes, so they read the grant the same way `deploy-guard.sh` does and stop with the
reason when it is `denied` (**never edit it yourself**). A Production-looking environment name stops them even
with the grant. Credentials come from the environment, as with `anypoint-api.sh`, so no secret on the command line.

**The most important measured finding: a wrong configuration key still returns 201.** `{"nosuchkey":1}` applied
successfully and showed up in the list as applied. **201 is not evidence that anything is protected.** It is now an
item in `gotchas/api-manager.md` (6 → 7), and the skill says to read `config` before writing and to decide
effectiveness by `policy-check.sh` exiting 0.

Verified live on a flexGateway instance: `find` / `config` / `list`, `apply` → **201** (version auto-resolved,
implementation asset auto-selected — applying `client-id-enforcement` installs `client-id-enforcement-flex`),
`remove` → **204** (gone from the list, original state restored), a wrong key returning 201, and both guards
(`policy.sandbox: denied`, Production-looking environment) stopping the script. The apply/remove round trip was
run once in the user's Sandbox and the original state was restored.

</details>

<details>
<summary><b>v0.6.41</b> — Values that live in Anypoint are fetched from the API. The "unresolved" gateway public URL is solved, and the lookup is now a tool</summary>

**v0.6.37 (PR #9) took in "a Managed Flex Gateway's public URL cannot be obtained from the API" as an
unresolved item, and v0.6.40's `mule-guide` told the agent to "have a human check the Runtime Manager UI".**
inventory3-api's T-007 followed that faithfully and stayed blocked, asking a human for the URL. The request was
"PR what you don't know and have it taken in as a skill" — and **the "don't know" itself had become the procedure.**
The PR was merged on this repository's side without checking the unresolved claim.

**The value was sitting in an API response.** Gateway Manager API, `getGatewayById`,
`configuration.ingress.publicUrl`. An API instance only carries the upstream and the listener inside the gateway
(`proxyUri`), so no amount of reading the instance shows it. What had been tried was API Manager and CloudHub 2.0
(the Private Space's `dnsTarget` and static IPs) — **2 of the 36 official APIs.** Searching every spec by field
name narrows it to 2 APIs in one step.

A lookup tool beats a long document for a weaker model (v0.6.40), so **the way to use the Platform API is now a tool.**

| Tool (new) | What it does |
|---|---|
| `scripts/portal-search.sh '<field>'` | Mirrors all 36 API specs from the official portal and searches by field name. Follows `$ref` up to **the operations that return the field in a response**, prints a ready-to-run `anypoint-api.sh` line, and says which list operation supplies each leftover path variable (`{gatewayId}`, from the spec's `x-origin`). Python 3 standard library only |
| `scripts/anypoint-api.sh '<path>' [--find <field>]` | Calls the Platform API **GET only**. Fills `{org}` `{env}` from the pom and sandbox.yaml, reads the secret from the environment (Sonnet had been writing `export ...SECRET=<value> && curl` each time, leaving it in the transcript). `--find` searches the response for a field |
| `scripts/gateway-public-url.sh <instance>` | Instance → gateway → public URL + the `proxyUri` path. Distinguishes "egress port: reachable only from inside" and "self-managed: whoever runs it decides" |

**The specs alone are not enough, as measured.** The Private Space's `dnsTarget` and `inboundStaticIps` that
Sonnet read exist in the real response but are not in the official spec. When `portal-search.sh` misses, it points
to "GET the list or detail and use `--find`", and that path (list → detail → `--find dns`) was confirmed to work.

Verified live (a managed gateway in a Private Space, 1.13.4; hostnames recorded as shapes):

| Called | Result |
|---|---|
| `gateway-public-url.sh inventory3-api` | `https://ft1-xxxxxx.<dnsTarget>/inventory3-api`. Same by ID or assetId |
| That URL + `/inventory` (no auth) | 401 `Client ID is not present` = the policy is answering |
| Without the trailing `/` / a path the gateway doesn't have | 404 |
| An API on the egress port (8082) | exit 1, "only from inside `http://ft1:8082/...`". 404 via the public URL |
| An API on a self-managed gateway | exit 1. `getGatewayById` returns 404 `Deployment not found` |
| Two instances with the same assetId | exit 2, listing candidate IDs |

**Two more things turned up.**

1. **`policy-check.sh` would have failed even with the right URL.** It GET-ed the first `*.req.json` as-is, which in
   inventory3 is `PUT /inventory/{inventoryId}/reserve` — a 405 with auth even when the policy works. A third
   argument now names the resource to GET; without it, a GET `*.req.json` with no path variables is picked. It now
   says what to do next for 404 (no route) / 401 (no contract) / 405 (not GET-able).
2. **inventory3 could bypass the gateway.** Through the gateway it gets 401, but the upstream is still the app's
   **public** URL, and hitting that without auth returns 200 for `GET /inventory`. This is the second occurrence of
   the first item in `gotchas/api-manager.md` (for a proxy, remove the app's public URL). `gateway-public-url.sh`
   now checks whether the upstream is reachable from outside and warns.

**The same mistake is now blocked by a machine.** `knowledge-index-check.sh` gained a fourth check: **an unresolved
item with no record of a `portal-search.sh` lookup does not pass.** `/mule-learn --share` runs it before a PR and
`promote-guard.sh` runs it as a hook, so "wrote 'cannot be obtained' without searching" no longer gets in (both the
rejection and the pass-with-record were confirmed).

`mule-guide` section 5 gained "how to get a value that lives in Anypoint", and section 7's "have a human look at
the UI" became `gateway-public-url.sh`. `mule-executor`, `/mule-run` ("cannot get it from the API" is not a reason
to block), `template/CLAUDE.md` and `gotcha-lookup.sh`'s miss message now follow the same order.

**Credential handoff is now concrete too.** Claude Code's Bash is a fresh shell every time, so "have them export
it" did not tell a human what to do, and Sonnet kept typing the secret it was given in chat onto the command line.
`anypoint-api.sh` and `deploy-precheck.sh` now ask the human to "export, then restart claude". **The template
`.gitignore` also excludes `.claude/settings.local.json`:** `!.claude/` re-includes `.claude/`, so a permanently
allowed command containing a secret could ride into a commit via `/mule-run`'s `git add -A` (applies to new projects).

Existing projects: `preflight.sh` names the three new scripts as "(missing)" and prints the `cp` command.

</details>

<details>
<summary><b>v0.6.40</b> — A step-by-step guide for Sonnet (`mule-guide`), and a tool that looks up known traps from an error's raw text</summary>

Prompted by "running on Sonnet feels like it knows nothing at all", the 16 ledger rows from inventory3-api
(a Sonnet run from the requirements document alone) were read. It got lost in three ways.

1. **The knowledge existed but was not found at the moment it was needed.** Flex Gateway's constraints were
   nearly all in `gotchas/api-manager.md`, yet it web-searched and trial-and-errored its way to the same
   conclusions repeatedly (PR #9).
2. **Prohibitions buried in long documents are not followed.** `CLAUDE.md` said "do not read outside this
   repository", and it read a neighbouring project's `pom.xml` to copy a GAV.
3. **It copies the reference templates faithfully.** Four rows came from following the plugin's own
   templates and scripts (fixed in v0.6.39). **Part of "knowing nothing" was the plugin teaching wrong things.**

**For a weaker model, a lookup tool beats a long document.** Reading an index to pick a topic is not
something you can do while staring at an error.

**`scripts/gotcha-lookup.sh '<part of the raw error>'`** (new) searches this project's K files and
`context/environment/` plus the plugin's gotchas and basics, and prints **whole matching items**. On a miss it
says what to try next (shorter words / INDEX.md / platform-assistant / the manual) and **what not to do**
(read neighbouring projects, guess and try). Of 10 raw error strings Sonnet actually saw in inventory3, 9 hit.

**Four of those hits existed only in inventory3's own K files** — general facts the next project would never
see. They were promoted into the plugin's gotchas (and confirmed findable from an empty directory, i.e. from
the next project's point of view):

| Fact | Now in |
|---|---|
| `output application/json` on `munit:payload` breaks later with `Stream Compatible` | `gotchas/munit.md` (14 → 15) |
| using `apikit:config` without adding `mule-apikit-module`, so its XSD cannot resolve | `gotchas/build.md` (14 → 15) |
| a `SET_...` placeholder in a numeric field (`port`) stops MUnit with `NumberFormatException` | `gotchas/config.md` (3 → 4) |
| `Number as String` drops `.0` (fix with `{format: '#0.0'}`) | `gotchas/dataweave.md` (3 → 4) |

**`skills/mule-guide/`** (new) is **a situation → next-action table**. You don't read it top to bottom; you open
the section for your situation and follow its numbered steps. Eight sections: an error appeared / before
writing / adding pom dependencies / writing MUnit / an unknown value / deploying / applying a policy /
stopping or asking a human — plus a "don't do this (do this instead)" table.

How it was written:

- **At most one line of reasoning.** History makes a weaker model lose track of which part is the procedure
  (the other skills carry a lot of history and rationale, written for a strong reader).
- **Commands are copy-ready.** The only placeholders are `<...>`.
- **Executors have no Skill tool and read SKILL.md as a raw file**, so it avoids `${CLAUDE_PLUGIN_ROOT}` and
  uses only project-local commands.
- **Every command and path was checked**: 16 scripts, 11 paths, all present. `anypoint-cli-v4 account
  business-group list` (written since v0.6.34) and `dx mule describe-connector` (written into gotchas) were
  **verified for the first time** — both exist.

**The entry point is handed over in one line**, because long rules drown inside a prompt: the top of
`mule-executor`, `template/CLAUDE.md`, and the prompt `/mule-run` dispatches all say "when lost, open
`mule-guide`; on an error, run `gotcha-lookup.sh` before any web search".

</details>

<details>
<summary><b>v0.6.33</b> — Three misclassifications in the exclusion list, and the criterion that closes it</summary>

**Confirming that a hook fires is impossible from any continuation of this session.** Even with the cache
up at 0.6.32 and matching the real copy, breaking the index and running `echo gh pr create` returned no
deny. **Hook configuration is read at session start and a context re-read does not replace it.** So the
chase stops here, closed by the note already in `knowledge/gotchas/build.md`: there is no way to verify a
hook by making it fire.

**Reviewing `checks-audit.sh`'s exclusion list found three of my own misclassifications.**

| | The error | Reality |
|---|---|---|
| `done.sh` | filed as "not a check" | **it is a check** — it runs `done_when` and returns its exit code, i.e. table row 11. Being excluded, its absence from the table could not be noticed |
| `checks-audit.sh` | in the exclusion list | **redundant, since it is in the table.** Listed entries exit earlier; having both reads as "not a check" |
| `mule-xml-shape.sh` | same | same (row 6b) |

Row 11 named only `done_when` and **not the thing that runs it (`done.sh`)**. It does now. The table went
from 21 rows to 22.

**Hand classification will always miss some.** So the **criterion** now heads the list:

> **Does it answer pass/fail with an exit code?** If so it is a check, and it belongs in the table.

The 12 that remain under that rule resolve paths, produce names, generate, patch a pom, log, report
metrics, inject, or install — **none of them answer pass/fail**. `plugin-root.sh` exits 1 when nothing is
found, but that reports absence rather than a verdict, so it stays excluded.

**With this, the 58 ledger rows and everything that came out of today's work are all handled.** All three
checks (index / fixtures / table) exit 0, and `gh pr create` is denied by a hook if any of them breaks.

</details>

<details>
<summary><b>v0.6.32</b> — Measured that the hooks do not fire, and the ordered table had one wrong row</summary>

**1. "A hook added today does not fire today" is now measured.**

Restarting the session is not something I can do — but **the absence of firing is observable.**
`echo gh pr create` matches `promote-guard`'s pattern while having **no side effects**. With the index
deliberately broken, it returned **no deny**. `deploy-guard`, present since v0.6.8, likewise returned no
deny when pointed at a project whose `deploy.sandbox` is `denied`. **Two independent hooks, neither
firing** — the hook configuration in force is the one loaded at session start.

**And one of my own claims turned out wrong.** v0.6.16 and v0.6.31 said the cache is materialised
**only at session start**; but the `0.6.25` cache is stamped 22:09 and `0.6.29` 22:26 — **both mid
conversation**. **What triggers materialisation is not observable from outside.** Only two things are:
"it is absent at the moment of the push", and "**a new directory appearing does not change the hooks in
force**". The assertion is withdrawn and rewritten as what was observed.

**2. Auditing the 20-row table against reality found one wrong row.**

The table was written in v0.6.28 to gather the checks scattered across the procedure docs — and it stood
**on the author's word alone**. Checking every row by machine for "does the script exist" and "is it
called from there", 19 matched and **`policy-check.sh` was invoked somewhere else entirely.**

| | The table said (wrong) | Reality |
|---|---|---|
| 18 | after applying a policy (`/mule-deploy`'s steps) | **the `done_when` of a `stage: policy` goal**, run by the executor; it appears nowhere in `/mule-deploy` |

**Anyone searching where the table said would not find it.** Like an index, **a table that has drifted is
worse than no table** — being written, it is followed without checking. Row 17 now also states that it is
both `/mule-deploy` step 5 **and** a `stage: deploy` goal's `done_when`.

**3. So the table is machine-held too.** `scripts/checks-audit.sh` (new) checks three things:

1. every script named in the table **exists**
2. it is **called from somewhere** (listed but uncalled means a check that never runs)
3. every existing check **appears in the table** — forget to add one and the "which are automatic, which
   rely on the procedure" list becomes a lie

**Item 3 caught one immediately** (`setup-deps.sh`; reading it showed it installs external skills for
`/mule-setup` and is not a check, so it is classified into the exclusion list). Teeth, three ways: remove
a row → `jar-leak-check.sh is not in the table`; name a nonexistent script → `no such file`; restore →
passes.

It is wired into `promote-guard.sh`, so **`gh pr create` is denied while the table has drifted** (the
table lists itself as row 21). It is in `/mule-learn --share`'s steps too.

</details>

<details>
<summary><b>v0.6.31</b> — A hook you add today is not running today, and hooks and knowledge come from different versions</summary>

`preflight.sh` ran end to end in both projects: **7 seconds, exit 0, no false positives** across all four
checks (git, root RAML, the `scripts/` comparison, `mvn clean package`). The jar mtimes confirm **mvn
actually ran** rather than being skipped with an "ok".

Then, checking whether the plugin's own `scripts/` (5 hooks + 3 checks) has the same staleness problem,
**a different and nastier mismatch appeared.**

**Hooks are read from the session-start cache and pinned there.**

```
newest cache: 0.6.29    ← where this session's hooks come from
the clone:    0.6.30    ← what plugin-root.sh returns; knowledge and skills come from here
```

`${CLAUDE_PLUGIN_ROOT}` in `hooks/hooks.json` is resolved by the harness **at session start** to a
version-pinned cache directory. **Fixing the real copy afterwards does not change the running session's
hooks.** The cache visibly accumulates a directory per session start: `0.6.8 → 0.6.25 → 0.6.29`.

**So `secret-guard.sh` and `promote-guard.sh`, both added today, never fired once today.** Nor did
`stop-guard.sh`'s new `goal-state.sh` call.

**Which is why every verification today was done by piping the hook's JSON straight into the script:**

```bash
printf '{"tool_input":{"file_path":"/tmp/x.md","content":"..."}}' | bash scripts/secret-guard.sh
```

**That is the correct method** (waiting for a firing that cannot come is not). But **unwritten, the next
person will assume the hook is protecting them**, so it is now written in three places:

- `knowledge/gotchas/build.md` (12 → 13) as symptom, cause, and verification method
- `/mule-learn` step 4: "that hook is not active in this session", with the command
- the ordered table's note on hooks

**Knowledge takes a different path.** `plugin-root.sh` picks the highest version (v0.6.16), so **hooks and
gotchas can come from different versions in the same session.** A wave leans on `wave-guard` /
`secret-guard` / `deploy-guard`, so `preflight.sh` now reports the split:

```
preflight: hook が古い可能性があります (cache の最新 0.6.29 / 実体 0.6.30)。
           ... 実体側で直した hook は次のセッションから効きます。
           この波でその hook に頼るなら、セッションを開き直してください。
```

**It does not assert "old".** Which cache the harness chose is unreadable from the shell
(`CLAUDE_PLUGIN_ROOT` is not in the environment — measured in v0.6.10), so it says "possibly".

For the same reason, v0.6.30's `scripts/` comparison now says **"differs" instead of "older"**. The error
showed up in practice: a pre-push copy was distributed by hand, so the project's file was *newer* while the
message called it older. **That script cannot know which side is newer.**

</details>

<details>
<summary><b>v0.6.30</b> — Stop having a human check whether the scripts actually got distributed</summary>

Auditing whether today's scripts reached both existing projects turned up **`bump-version.sh` and
`ch2-public-url.sh` stale in both** (from v0.6.15, when the gotchas references moved to per-topic paths).
The diff was comment-only this time — but **it was noticed only because the audit was done by hand.**

`/mule-init` copies `template/` **wholesale, not by enumeration**, so a new project picks up new checks
automatically. **An existing project does not.** A missing check goes unnoticed **until the step that
calls it falls over.**

`preflight.sh` now compares before dispatching a wave and **names** what is missing or stale:

```
preflight: scripts/ がプラグインより古いものがあります: teeth-check.sh(無し) goal-state.sh(古い)
           直す: cp <plugin>/template/scripts/*.sh scripts/ && chmod +x scripts/*.sh
           (波は止めません。検査が欠けたままだと、その検査が受け持つ失敗を取り逃します)
```

**It does not stop the wave.** A one-line `cp` fixes it, and stopping would block all work. Anything that
must stop is stopped by the check itself (a missing check fails when it is called). **That decision is in
the table too** — after v0.6.29's lesson that a check placed too late prevents nothing, **what stops and
what merely reports is visible at a glance.**

Measured three ways: all present → silent; remove one → `teeth-check.sh(無し)`; make one stale →
`goal-state.sh(古い)`. The comparison target is whatever `plugin-root.sh` picks **by version**, so it
compares against the right copy even in the session right after a version bump (v0.6.16).

Both projects are now in sync across all 22 scripts (`finance-api`'s `contract-check.sh` is
project-specific and out of scope).

</details>

<details>
<summary><b>v0.6.29</b> — Move the "forgettable" checks into hooks. One of them was placed too late to prevent anything</summary>

Ordering the 20 checks in v0.6.28 made one thing visible at a glance: **only 3 were hooks; the other 17
are invoked by the procedure docs** — and a procedure-invoked check that is forgotten is a check nobody
misses. Sorted by what happens when it *is* forgotten, three moved into hooks.

**First, the ordering exposed one of my own errors.** v0.6.27 placed `jar-leak-check.sh` **after** the
publish. Checking a jar that ignores `.gitignore` *after* it reaches Exchange **cannot undo anything** —
at that point the whole org can read it.

```
v0.6.27:  mvn clean deploy → mvn deploy -DmuleDeploy → jar-leak-check   ← too late
v0.6.29:  mvn clean package → jar-leak-check → mvn deploy → mvn deploy -DmuleDeploy
```

**A check placed too late prevents nothing.** So the ordered table now always states *when*, and row 16
reads "after `mvn clean package`, before `mvn deploy`".

**The three that moved:**

**14 → `stop-guard.sh` now calls `goal-state.sh`.** Whether a goal can still advance is machine-decidable,
yet it was a procedure-invoked check. **The moment before stopping is the only place a hook can act**, so
it acts there. It bounces only on exit 1 (can advance) and **passes exit 2 (waiting on a human) and exit 0
(done)** — so it never obstructs correct waiting. Measured three ways: a todo → bounce; all passed → pass;
`status: blocked` → pass.

**7b → `promote-guard.sh` (new).** In the plugin repo, `gh pr create` requires
`knowledge-index-check.sh` and `fixtures-check.sh` to pass. Forgetting them is nasty: a drifted index
makes readers conclude "no row matches" and never open the file, so **the item is read by nobody**
(v0.6.15 got 19 numbers wrong; PR #2 left a count at 11). A toothless hook passes everything while looking
like a guard. **Both only bite after a merge**, so opening the PR is the last gate. Measured four ways:
passing → silent; drifted index → deny with the raw output; a non-`gh pr create` command → ignored;
**a user project without the check scripts → does nothing**.

**7 → `deploy-guard.sh` also inspects the jar.** If step 16 is skipped but `target/` holds a leaking jar,
the deploy command is denied. With no jar it says nothing (one is about to be built). Measured two ways:
leak → deny, naming the file; removed and rebuilt → allow.

**What did not move**, for the record: forcing `preflight` / `budget-check` from a PreToolUse hook on the
`Agent` tool was **rejected** — `Agent` serves more than executors, and **the false positives would cost
more than the forgetting**. Rows 8–12 (checks inside a single goal) have no tool boundary to hook, so the
procedure and `mule-tdd`'s evidence block carry those.

`mule-status`'s "what to do next" table now keys off `goal-state.sh`'s exit code too — counting states by
eye gets it wrong every time, because `blocked` carries two meanings.

</details>

<details>
<summary><b>v0.6.28</b> — A machine answers "is it OK to stop", and the 20 checks are ordered</summary>

The last row left in the ledger was the `/goal` one: a condition like "everything passes" reads remaining
goals that are **legitimately waiting on human authorization** as "not done yet", and re-fires even when
the same report is repeated.

The cause was not only on `/goal`'s side. **`blocked` carried two meanings, and neither was machine
readable:**

1. `attempts` reached 3 and the agent gave up
2. `authorizations.yaml` says `denied`, so the stage cannot be entered

Both mean "not one step is possible until a human moves", and **no amount of agent effort changes them.**
On top of that, a goal merely waiting on an unfinished `blocked_by` is *waiting*, not stuck — so counting
states by eye gets it wrong every time.

**`template/scripts/goal-state.sh`** decides from the ledger plus `authorizations.yaml` and answers by exit
code:

| exit | Meaning | `/mule-run` |
|---|---|---|
| 0 | every goal passed | report completion |
| 1 | **a goal can still advance** | **keep going unless you can justify stopping** |
| 2 | nothing can advance and it isn't done | **waiting on a human; stopping is correct** |

"Can advance" means `status` is `todo`, or `failed` with `attempts < 3`; and every `blocked_by` is
`passed`; and the stage is authorized (`stage: deploy` needs `deploy.sandbox: allowed`).

**Phrase `/goal` conditions as "`goal-state.sh` exits 0 or 2", not "everything passes."** That way both
"done" and "the agent side is out of moves" satisfy the condition. `/mule-run`'s prohibitions gained
**"editing `authorizations.yaml` to get past an exit 2"** — that is a human's call, and waiting is the
correct behaviour.

Teeth, six ways. Both projects are complete, so only exit 0 ever appeared — and **a check that only ever
returns one value is indistinguishable from a broken one** — so a ledger was built to walk every branch:
a todo → 1; a deploy goal with authorization denied → 2; **flipping it to allowed → 1**; `attempts` 3 → 2;
`status: blocked` → 2; all passed → 0.

**And the checks are now ordered** (`docs/methodology.md`, "検査の並び (走る順)").

The existing "4 validator tiers" table sorts **code validators by speed**; the checks that actually run in
one pass are more than that, and they were scattered across the procedure docs. All 20 are now in one
numbered list with **when each fires, what it withholds, and its exit contract**. An extract:

```
 2 before dispatch   budget-check.sh    → dispatches nothing
 3 before dispatch   preflight.sh       → dispatches nothing
 4 before a write    secret-guard.sh    → denies the write (hook)
10 inside a goal     teeth-check.sh     → no toothless test survives
14 before stopping   goal-state.sh      → answers whether stopping is OK
16 before shipping   jar-leak-check.sh  → does not deploy
17 after deploying   smoke-check.sh     → does not call it done
20 before promoting  fixtures-check.sh  → does not claim promotion
```

**Three are hooks (4, 5, 7) and run even if the agent forgets.** The rest are invoked by the procedure, so
forgetting is possible — **which is why the table exists**: to make it visible at a glance which are
automatic and which rely on an agent. `/mule-run` carries only a pointer to it, so **the same content does
not live in two places** (the same reason an index must not drift from reality).

</details>

<details>
<summary><b>v0.6.27</b> — The last 9 rows: 6 already recorded, 1 defect in this plugin's own steps, 2 new hooks</summary>

`dataweave-null` 2 + `secret-leak` 2 + `deploy-*` 5 = 9 rows. **Six were already at their destination:**

| Ledger row | Where it already was |
|---|---|
| `payload as String` → `Cannot coerce` (×2) | `gotchas/apikit-http.md` + `basics/dataweave.md` |
| `oracle.jdbc.OracleDriver` → `Cannot load class` | `basics/db.md`'s "a JDBC driver is needed in **two** places in the pom". Checking the pom, `<sharedLibraries>` is exactly how it was fixed |
| ORA-12505 / ORA-00942 / wrong service (×3) | inventory2-api's `context/environment/resolved.md`, with the connection string and measurement dates |

**Which means the destination table works.** Without the rule sending `environment-fact` to
`context/environment/` (v0.6.12), Oracle's SID-vs-Service-Name story would have gone into the
all-projects gotchas and **become false for every other project.**

**One of the remaining three was a defect in this plugin's own instructions.**

`mule-deploy` wrote `mvn clean deploy -DmuleDeploy` as **one command**. Followed literally it **always**
fails with `Failed to retrieve artifact information from Exchange. Reason: 404 There is no asset matching
given parameters.`, because `muleDeploy` reaches for an asset that has not been published yet.

- The step is now two stages: `mvn clean deploy` (publish only) → `mvn deploy -DmuleDeploy` (deploy),
  noting that a `clean` on the second stage destroys the artifact and forces a re-publish.
- The same 404 appears when `<businessGroupId>` is missing (the token's **default org, Root**, is used).
  `deploy-config.sh` now writes it from the pom's `groupId`.
- `gotchas/deploy.md` (6 → 7) records the symptom and cause.

**Two new checks, both built to avoid guessing values or patterns.**

**`jar-leak-check.sh`** — `-DattachMuleSources` archives **the entire project from the filesystem** into
`META-INF/mule-src/` and **does not consult `.gitignore`**. Measured: a `.gitignore`d file holding a
plaintext DB password went straight into the jar. It was never in git, so `git log -S` finds nothing, and
the jar goes to Exchange where the whole org can read it. **Only the person shipping it can notice.**
The test is "**does the jar contain files git ignores**" — fewer false positives than name patterns, and it
catches files not named `credential`. Wired into `mule-deploy` step 3b.

Two self-inflicted bugs along the way, both making **the check itself silently return ok**:

- it `cd`'d to `git rev-parse --show-toplevel`, so in a monorepo (inventory2-api's git root is
  `mule-demos`) `target/*.jar` was never found: "no jar". → the `cd` is gone
- `git check-ignore --stdin` exits 128 with `fatal: empty string is not a valid pathspec` **if one line is
  empty**, and `|| true` swallowed it into "no leak". → empty lines are dropped, and **any exit other
  than 0/1 now reports "could not determine" instead of ok**

**`secret-guard.sh`** (PreToolUse Edit|Write) — credentials were once **nearly written into three tracked
files** as a progress note, and the ledger's remedy was "be disciplined about grepping before commit".
That is a rule, enforced by the same party that broke it. So a machine enforces it.

**It does not guess at secrets by pattern; it matches the values themselves.** The sources are where
secrets legitimately live (`ANYPOINT_CLIENT_SECRET` / `ANYPOINT_CLIENT_ID`, `<password>` in
`~/.m2/settings.xml`), ignoring anything under 8 characters. So it is independent of variable names and
encodings (base64 or UUID alike) and never flags a non-secret. **`${env.X}` references are not flagged.**

**It never prints the value.** Hook output enters the conversation, so printing the secret there would
defeat the point. `fixtures-check.sh` now **tests that the deny reason contains no value.**

Teeth (`bash scripts/fixtures-check.sh`, all 8): writing the value → deny; the deny reason carries no
value; a write without the value → passes; `${env.X}` → passes. The jar check, three ways: leak → exit 2;
removed and rebuilt → exit 0; no `attachMuleSources` → not applicable.

</details>

<details>
<summary><b>v0.6.26</b> — One claim in the reference template was never verified. Measured, it was false</summary>

The 8 `munit-coverage` + 4 `munit-mock-missing` rows were **all 12 already covered on the plugin side**
(`gotchas/munit.md`, `mule-munit`, `router-test.xml`, `teeth-check.sh`). What remained was project work:
inventory2-api's **toothless router-flow tests**.

**Toothlessness was demonstrated by machine first** (measured, not argued — one of `teeth-check.sh`'s first
jobs): changing the mock's return from `#[[]]` to `#[[{}, {}]]` still gave `Tests run: 1 - Failed: 0`.
A test that only checks `vars.httpStatus` is non-null passes either way, by construction.

Four were replaced with `router-test.xml`'s typed-attributes shape, **comparing the response body against
the samples**. Their `behavior` mocks were **copied by machine** from the approved tests (copying by hand
drifts). All four measured as having teeth (break the mock's return, or repoint the expectation at a
different sample → the intended case reports `Failed: 1`). All 15 suites green,
`flow coverage: 12/12 (100%)` held.

**Which is where the template's own error surfaced.** `template/reference/router-test.xml` said:

> **Calling the main flow** (listener + apikit:router, when you want real APIkit validation): APIkit
> resolves the route and schema, so `method` / `listenerPath` / `relativePath` / `requestPath` and the
> `content-type` header are what matter.

**Never verified. Measured, it does not hold:**

- typed attributes plus `flow-ref` still yields `APIKIT:NOT_IMPLEMENTED`
- `maskedRequestPath`, which APIkit routes on, **cannot be supplied from DataWeave** —
  `Unable to found builder method: maskedRequestPath() on class HttpRequestAttributesBuilder`.
  In mule-http-connector 1.10.6 **the field exists** but the builder has no setter, so there is no way in
- `listenerPath: "/*"` with `requestPath: "/inventory/1"` still gives `NOT_IMPLEMENTED`

This is **the same species** as the v0.6.23 fix (one target's measurement written as a universal fact).
There the basis was one measurement; here it was zero. **The writer cannot tell the difference. The reader
follows without checking.**

- `router-test.xml`: the claim is replaced with the measurement, **and the fact that it was unverified**
- `gotchas/munit.md` (13 → 14) and `mule-munit`: "a main flow cannot be routed via `flow-ref`"
- inventory2-api's `api-main-test.xml` **cannot be given teeth**, so it stays with the reason written in,
  explicitly saying **do not rebuild it thinking typed attributes will work**. APIkit's routing is covered
  by stage 4 (`smoke-check.sh`, which only started working in v0.6.25).

</details>

<details>
<summary><b>v0.6.25</b> — The post-deploy contract check had never once landed (two parts of this plugin disagreed on the sample shape)</summary>

Working through the 10 `loop-ops` rows, **8 were already mechanized or addressed**:

| Ledger row | What covers it |
|---|---|
| worktree needs an initial commit | `/mule-run` step 4 |
| K filename collisions | `k-new.sh` (v0.6.13) |
| worktree base older than the goal commit (×2) | the v0.6.7 measurement + the isolation decision table |
| dispatcher broke its own file-ownership split | `wave-guard.sh` (v0.6.14) |
| a relative path in a worktree resolved into another project | absolute paths + goal content pasted into the prompt (v0.6.7) |
| worktree base pinned per session | the table routes to no-isolation (reported as a product bug) |
| `/goal` reads "blocked" as "not done" | **unresolved**; needs mechanism on the `/goal` side |
| `smoke-check.sh` does not know the sample shape | **fixed here** |

**The one that was left was a disagreement inside the plugin itself.** Acceptance samples use MUnit's
input shape:

```
in.json  {"inventoryId": 3, "body": {"quantity": 5.0}}
out.json {"status": 200, "body": { ...response body... }}
```

but `smoke-check.sh` **sent the whole file as the HTTP body** and **compared the response to the whole
out.json**. So:

- the body sent was `{"inventoryId":3,"body":{...}}` (only `.body` should go)
- the expected value was `{"status":...,"body":...}`, which a response body cannot equal
- **the status code was never compared** even though out.json carries it
- the default path was `POST /<resource>` where the real one is `PUT /inventory/{inventoryId}/reserve`

**Which means the post-deploy check had never actually landed.** Stage 4 of `docs/methodology.md`
(contract check against the deployed app) exists as the **last line of defence** for what MUnit cannot see
in principle — SQL, types, double-wrapping. It was swinging at air. The ledger recorded it as one
inventory2-api row; **measured, finance-api has the same shape**, so both were broken.

Fixed:

- **Body**: send only `.body` when `in.json` has one (whole file otherwise — backward compatible)
- **Expected**: when `out.json` has `status` and `body`, compare **both, separately**; a status mismatch
  reports as `status(409≠200)`
- **method/path derived from the RAML**: enumerate methods and paths from `api/*.raml` and pick by
  (1) the path's last segment matching the case name's first token, (2) the path containing the resource
  name, (3) **the path's `{...}` exactly matching in.json's top-level keys**, (4) body presence agreeing
  with the method. Without (3), `get-ok` resolved to the collection `GET /inventory` — **item vs
  collection confusion**.
- **Query string**: `in.json`'s `query` is appended to the URL (the shape search samples use)
- **`--dry-run <base>`**: print what would be sent. **Verifiable before deploying.**

Under `--dry-run`, **all 25 cases** across both projects resolve to the right method, path, and query from
the RAML, with nothing falling back to the default:

```
inventory/reserve-ok   PUT  https://x/api/inventory/3/reserve  (RAML)
  body:     {"quantity":5.0}
  expected: status 200 / body {"inventoryId":3,...}
inventory/search-ok    GET  https://x/api/inventory?warehouseCode=WH-MAIN&lowStockOnly=true  (RAML)
name/not-found         PUT  https://x/api/customers/CUST99999/name  (RAML)
```

`.req.json` remains as the explicit override (its `path` gets `{...}` substitution too).

</details>

<details>
<summary><b>v0.6.24</b> — Two RAML/sample drifts a machine can catch. One found more than the ledger recorded</summary>

Of the 5 `raml-mismatch` rows, 3 were already in `gotchas/apikit-http.md` and are semantic (base path in
`requestPath`, the `error.description` format, a status pinned by an earlier test). **Both of the other two
turned out to be machine-catchable.** New: `template/scripts/spec-check.sh`.

**Check 1: samples exercising the same flow must agree on the shape of `instance`** (exits 2)

Which sample belongs to which flow is **something MUnit already knows** (a `munit:test`'s `flow-ref` plus
its `readUrl("classpath://samples/...")`). **Filenames are not guessed from** — finance-api uses
`not-found.out.json` and inventory2-api uses `reserve-not-found.out.json`, so a name-based grouping works
in one project and not the other (written that way first, it collapsed finance into groups of one).

The ledger says "`reserve-not-found`'s `instance` was missing `/reserve`". Run for real, **2 of 3 were
broken**:

```
flow reserve-inventory:
  2 segments  /inventory/999          (reserve-not-found.out.json)
  2 segments  /inventory/1            (reserve-upstream-error.out.json)   ← not in the ledger
  3 segments  /inventory/3/reserve    (reserve-insufficient.out.json)
```

**It runs before the human approves** (`/mule-run` step 3). Found afterwards, the samples fall under
"never change an expected value", so only the implementation can move — which is exactly what happened:
inventory2-api reshaped `reserve-inventory` into a two-stage "re-append `/reserve` only after the lookup"
to match approved samples. **Before approval, fixing the samples is the cheapest move.**

**Check 2: a RAML-required property that appears nowhere in the implementation** (**warning only**)

This is the `ReserveRequest.lastUpdated` row — required in RAML, never read, found by `mule-reviewer`
reading the code. A machine can spot the same thing. **But it does not exit 2**: for a pass-through API
that forwards the received body, the name legitimately never appears, so **a machine cannot decide
right from wrong**. It runs first in `mule-reviewer`'s check 2, and the reviewer reads the implementation
to judge — neither swallowing nor ignoring the output.

**Both checks were verified to have teeth.** Check 2 was silent in both projects (`lastUpdated` is already
fixed), and silent is indistinguishable from toothless, so it was tampered: adding a required property
absent from the implementation produces
`PUT /inventory/{inventoryId}/reserve の ReserveRequest.zzzNeverReferenced`. A property marked
`required: false` is correctly **ignored**. Both RAMLs were restored. Check 1 passes all 4 flows in
finance-api (no false positives) and reports the above in inventory2-api.

</details>

<details>
<summary><b>v0.6.23</b> — One line of the shared knowledge was false (one target's measurement written as a fact about all)</summary>

Working through the 5 `connector-behavior` + 2 `environment-fact` rows, **5 of the 7 were already
recorded**, and both `environment-fact` rows had landed where they belong, in
`context/environment/cif-schema.md`. The two left over were **the same class with opposite conclusions**,
which is how the error in the shared knowledge surfaced.

`knowledge/gotchas/db.md` and `basics/db.md` said:

> A TIMESTAMP column arrives in Mule as a **DataWeave `String`** (`2026-09-05T16:47:13.033`, no TZ).
> `as String` is the identity.

**Stated flatly — but the basis was a single Derby measurement.** On Oracle it's the reverse:

| Target | Type `db:select` hands DataWeave | `as String` |
|---|---|---|
| Derby (clouderby-jdbc) | already a `String` | harmless identity |
| Oracle (`db:generic-connection`) | a raw `Object` | **fails** (`Cannot coerce Object to String`) |

inventory2-api actually returned 500 because of it. **And MUnit was green across all 15 suites** — the
`mock-when` returned a plain string, so the type mismatch vanished into the mock. It surfaced only when
the app was deployed and hit with curl.

- `gotchas/db.md` (6 → 7 items): both measurements now sit side by side in their own item, which states
  inside itself that **a measurement from one target must not be written as a fact about all of them**.
  The remedy is "don't rely on the type in dwl; stringify in SQL with `TO_CHAR`", applied to **every**
  SELECT reading that column (the optimistic-locking comparison read the same one).
- `basics/db.md`: the line now says the type depends on the DB and driver. **Its marker went from `[K]`
  to `[G]`**, since it is now measured in two projects.
- `gotchas/munit.md` (12 → 13) and `mule-munit`'s "what MUnit cannot verify" gained
  **"the type a `mock-when` returns need not match the real connector, so type mismatches stay green"**.
  **The fix is not to make mocks resemble reality** — you get it wrong precisely because the real type is
  unknown.
- `gotchas.md`'s append rules gained **"a fact measured on one target must name that target in the
  text"**. If its scope closes over a single target, the destination is `context/environment/`.

Both index counts were **stopped at exit 1 by `knowledge-index-check.sh`** before being corrected
(db 6→7, munit 12→13) — the v0.6.17 gate earning its place a second time.

</details>

<details>
<summary><b>v0.6.22</b> — The 5 `error-handler` rows were fine as prose. What was missing was one template</summary>

Going through the 5 `error-handler` rows (finance 4 + inventory2 1), **nothing warranted mechanizing.**

| Ledger row | Verdict |
|---|---|
| `try-scope-resume-after-continue` (resume position) | Semantics; a machine cannot judge it. Already in `gotchas/error-handling.md` |
| `shared-handler-propagate-breaks-others` | Same; a design choice, not something to deny |
| `builtin-error-type-not-raisable` | The build fails **loudly**. The remedy is already prose |
| `custom-error-type-undeclared` (**two projects**) | Also loud. **But there was no template** |

Denying `custom-error-type-undeclared` in a hook was **rejected**. Under TDD you write
`on-error-continue type="APP:X"` and *then* the `raise-error`, so **denying that intermediate state fights
the correct procedure.** The build says `Could not find error 'APP:X'` explicitly — this never passes
silently. What was missing was what to write instead.

**When a wave writes `global.xml` first, the goals that implement the resource flows have not run yet.**
"Write the real `raise-error` later" doesn't fit — the build fails at that moment. inventory2-api solved it
by **inventing a type-registration stub**. Per the v0.6.14 table a template earns its place on one
occurrence, so it's now in `template/reference/`:

- `global.xml` gains `app-error-types` (a `sub-flow`): it raises only the type named by
  `vars.appErrorTypeToRaise` and, with nothing set, **returns doing nothing** via `otherwise` — which is
  what makes it safe to call from MUnit (`coverage-check.sh` requires every flow to be `flow-ref`'d from a
  test). The comment also says it **may be deleted** once the goals write the real ones.
- `error-types-test.xml` (new) is its MUnit.

**Which is where the original's toothlessness showed.** inventory2-api's stub test was
`expression="#[true]" is="#[equalTo(true)]"` — passes coverage, verifies nothing. With
`expectedErrorType` the same effort verifies **that the type can actually be raised**, i.e. the stub's
entire reason for existing. The template uses that shape, and `expectedErrorType` was confirmed in
`mule-munit.xsd` rather than recalled.

**The template was measured before being shipped.** Run for real in inventory2-api:
`Tests run: 2 - Failed: 0`, then teeth measured with v0.6.21's `teeth-check.sh` (swap the expected type →
the intended case reports `Failed: 1`; repoint `vars.probe` at a missing variable → the no-op case reports
`Failed: 1`). **The new teeth tool's first job was measuring the new template's teeth.**

inventory2-api's `#[true]` test was replaced with this shape, keeping `flow coverage: 12/12 (100%)` and
gaining verified teeth.

</details>

<details>
<summary><b>v0.6.21</b> — Stop measuring teeth by hand (three times, the measurement itself missed)</summary>

Going through the ledger's 6 `test-toothless` rows one at a time, the breakdown was not what was expected.
**5 of 6 were "the check never ran at all"**, and **3 of those were "the teeth measurement itself missed"**:

- `tamper-missed-due-to-line-number-drift` — a line-pinned `sed` landed nowhere, so **not one character
  of the tamper applied**, and green was nearly read as "no teeth"
- `mutation-test-wrong-failure-path` — a different prelude failed first, exit 1, and **the intended case
  never ran**
- `uncaught-exception-in-check-prelude` — an exception in the prelude printed a stack trace, zero NG
  lines, exit 1

One shared mistake: **treating a non-zero exit as proof of teeth.**

v0.6.11 wrote this into `mule-munit` as **prose** — "measure these three things." Prose isn't enough; all
three rows above are things "be careful" was supposed to prevent. It now lives in
`template/scripts/teeth-check.sh`:

```bash
bash scripts/teeth-check.sh --file src/test/munit/name-test.xml \
     --old 'samples/name/not-found.out.json' --new 'samples/name/ok.out.json' \
     --case name-not-found
```

A machine checks all three: **did the tamper land** (refuses unless the anchor occurs exactly once; no
line numbers) / **was it green before** / **did the intended case appear as a failure**. The target file is
restored even on abnormal exit.

**MUnit's output format was measured, not recalled** — from finance-api's `name-test.xml`:

```
before: = Tests run: 7 - Failed: 0 - Errors: 0 - Skipped: 0 ... =
after:  munit.01 ERROR FAILURE - test: name-not-found - Time elapsed: 0.03 sec
        = Tests run: 7 - Failed: 1 - Errors: 0 - Skipped: 0 ... =
```

So the conditions are `FAILURE - test: <case>` plus `Failed:` of 1 or more.

**The teeth check was verified to have teeth, six ways, against real mvn runs** (so this check does not
itself become a `test-toothless` row):

| Tried | Result |
|---|---|
| anchor occurs 0 times | exit 2 |
| anchor occurs 3 times (`equalTo(vars.expected.status)` really does appear 3×) | exit 2 |
| misspelled case name | exit 2, **before `mvn` runs** |
| expectation repointed at a different sample | **exit 0 (has teeth)**; `Failed: 1` and the case name confirmed |
| tampered only a `doc:name` (nothing an assert reads) | exit 2, "**no teeth**" |
| tampered a *different* case, left `--case` alone | exit 2, "**a different case failed**", naming it |

The last two are the point. The fifth is the branch that **finds toothless tests**; the sixth is
**`mutation-test-wrong-failure-path` itself**, now caught by a machine.

Two fixes along the way. On `Failed: 0` it said "a different case failed" (different cause, different
remedy — the tally is now checked first). And the tamper display moved from `grep` to a **diff**: another
case read the same sample, so three lines unrelated to the tamper were being listed.

`mule-munit` lost the three-step prose procedure; `mule-tdd`'s evidence block gained a `teeth:` line.

</details>

<details>
<summary><b>v0.6.20</b> — The schema index goes silently undelivered if it's ignored, so say when it is</summary>

Reviewing the two projects' uncommitted changes, `reference/mule-schema/` turned out to be **untracked** in
both. The v0.6.7 measurement is what makes that matter: **`isolation: "worktree"` worktrees are cut from
`origin/main`, so an untracked file never reaches an executor at all.**

Which breaks something specific. `agents/mule-executor.md` and `mule-munit` both say
**"never guess a connector's element, operation, or parameter names"** and point at `INDEX.md`. With no
index, the prohibition is all that survives and **guessing is the only option left** — the exact thing the
script was built to remove.

Neither project was actually broken: `/mule-run` runs `git add -A` before dispatching, so anything not
excluded by `.gitignore` gets committed (and both are tracked now, after this review). The dangerous case
is **only** when it *is* excluded — and then it goes undelivered with no message.

- `scripts/preflight.sh`: if the index matches `git check-ignore`, **say so, with the reason. The wave is
  not stopped** — without the index an agent can still fall back to gotchas → skills, which is a cost, not
  a broken foundation. It sits **after** `mvn package`: a wave whose build fails dispatches nothing, so the
  warning would be noise there.
- `scripts/schema-index.sh` now states in its header that **the output must not be added to `.gitignore`**,
  and why. It is 564 KB of generated files, so wanting to exclude it is the natural instinct.

All three branches verified: ignored → warns; not ignored → silent; index absent → silent.

</details>

<details>
<summary><b>v0.6.19</b> — No `mule-build` skill. Mechanize the 3 of 8 rows a machine can catch</summary>

The plan was a `mule-build` skill covering the ledger's 6 `build-config` + 2 `xml-namespace` rows.
**It wasn't written.** Going through the 8 rows one at a time, **7 were already in `knowledge/gotchas/`**,
so the skill would have been a third copy (gotchas original → basics summary → skill) — giving back part
of what v0.6.15 just bought.

The v0.6.14 table settles it: **what a machine can catch does not become prose.** By destination:

| Ledger row | Already recorded in | Done here |
|---|---|---|
| `db:sql` written as an attribute | `gotchas/db.md` | **denied by hook** |
| `error-handler` position inside `<try>` | `gotchas/error-handling.md` | **denied by hook** |
| root-level `api/*.raml` not on the classpath | `gotchas/build.md` | **stopped in preflight** |
| `dw validate` false positive on `p()` | `gotchas/dataweave.md` | `quick-check` already filters it |
| `.gitignore` missing `target/` | — | already in the template |
| mixed JDK (`javac` vs `java`) | `gotchas/build.md` | a fact about the machine; stays prose |
| env vars don't override properties | `gotchas/config.md` | same |
| vendor JDBC jar is not fat | **was missing** | appended to `gotchas/build.md` (10 → 11) |

**`scripts/mule-xml-shape.sh`** — `xmllint --noout` only checks well-formedness, so shapes that fail XSD
sail through. And `xmllint --schema` is not an option: **connector XSDs are not in the jars.** A jar ships
`*-extension-descriptions.xml` (documentation); the XSD is generated by the runtime from the extension
model. Measured: of the 21 files extracted from `~/.m2`, the `.xsd` files are all runtime-side.
**So it validates nothing in general and checks only fingerprints the ledger measured.** The content
models were copied from `mule-core-common.xsd` rather than recalled:

- `flowType`: `description?, messageSource?, processor+, abstract-error-handler?`
- `tryType`: `processor+, abstract-error-handler?`
- `subFlowType`: `description?, processor+` — **cannot hold an error-handler**

**A root-level `<error-handler name="global-error-handler">` is unconstrained and is not checked.**
`template/reference/global.xml` has exactly that shape; flagging it would fail the reference skeleton.

Teeth (`bash scripts/fixtures-check.sh`): the three violating shapes exit 2 and **the legal shape passes**.
The inputs live in `knowledge/fixtures/`. For a hook that denies, **a false positive blocks editing**, so
testing only the deny side is not enough (the ledger's `dw-validate-false-positive-p` is the precedent).
`/mule-learn` step 4 now requires adding an `ok-*.xml` too.

**The preflight RAML check is not caught by `mvn package`.** Package succeeds; the failure is at app init
(`InitialisationException: Raml not found`). Ledger T-001 lost a goal *after* a passing package, which is
why this runs **before** it. Projects that keep the RAML under `src/main/resources/api/` are on the
classpath already and are not checked.

Appending to `gotchas/build.md` **exercised the v0.6.17 index gate for real**: before the count was fixed,
`knowledge-index-check.sh` reported "index says 10, disk says 11" and exited 1.

</details>

<details>
<summary><b>v0.6.18</b> — Without git, four mechanisms silently become no-ops. Stop the wave in preflight</summary>

**This entry was first written on a false premise.** While redistributing scripts to existing projects I
found `/home/myst/projects/inventory2-api` was not a git repository and wrote that a project with real
history had been running without git. **That directory was an empty one I had just created with
`mkdir -p`**; the real project lives elsewhere and is a git repository on `main`. The error was
**asserting a fact about a project from a path I had not verified.** Rewritten with the actual basis.

The check stays, because its justification is not an incident but **what the code says**:

- `wave-guard.sh` **passes through with `exit 0` by design** outside git (so it never misfires in a worktree)
- **worktree isolation** cannot be created without git (parallel goals then share one tree)
- the **"is a K file in the diff" check** has no diff to read
- **`/mule-learn --share` PRs** cannot be opened

All four do **nothing, with no error and no warning**, when git is absent — the opposite of everything else
here: `deploy-guard` returns a deny, `wave-guard` returns a deny, `coverage-check` returns exit 1.
**A check that silently does nothing is worse than no check** — you proceed believing it held. So it gets
the same treatment as a missing `pom.xml`: `scripts/preflight.sh` verifies git first and **exits 2,
dispatching nothing**, naming all four mechanisms and printing the one-line `git init` remedy.

Teeth verified: exit 2 in a non-git directory; after `git init` it proceeds to the next check (mvn package).

</details>

<details>
<summary><b>v0.6.17</b> — Stop hand-holding the numbers in the index (v0.6.15 broke them exactly as its own note warned)</summary>

The v0.6.15 index tables carried line counts, written **before** the per-file headers were compressed by
one line. All 19 numbers ended up off by one — inside the same commit whose note says "an index that
drifts from reality means readers conclude no row matches and never open the file" and cites PR #2
leaving a count at 11. **The person writing the warning can break it in the same commit.**

So the numbers were taken away from the human.

- **The line-count column is gone.** Line counts move on every edit to any topic file and have **zero
  bearing on which topic a reader opens**. They were never worth maintaining.
- **Only the item count stays, and a machine checks it.** Item counts move only when an item is added —
  the same moment `/mule-learn` already touches the index. `scripts/knowledge-index-check.sh` checks
  three things: every file on disk has a row, every row has a file, and each count equals the number of
  `## ` headings. Hand-maintained numbers went from 28 to 9, and a machine holds those 9.
- `/mule-learn --share` runs it before `gh pr create` (exit 0 required). **A PR that appends an item and
  forgets the index fails before it is opened.**
- The script lives in `scripts/` (the plugin itself), **not `template/scripts/`** — the indexes live in the
  plugin and are never distributed to user projects, so shipping it there would give it nothing to check.

Teeth verified three ways: setting a count 12 → 11, adding a topic file absent from the index, and
deleting a file the index points at all exit 1. (If any one of those passed, the check would be theatre.)

The prose rule "fix the index count when you append" was **removed** from `/mule-learn`. Per the v0.6.14
table, something a machine can catch does not become a sentence.

</details>

<details>
<summary><b>v0.6.16</b> — plugin-root.sh was handing back a stale version (the cache is only built at session start)</summary>

Right after pushing v0.6.15, `bash scripts/plugin-root.sh knowledge/gotchas/munit.md` answered
**"not in the plugin"**. The file exists. What the script had picked was v0.6.8.

The delivery chain is working repo → push → the `marketplaces/` clone → `cache/<marketplace>/mule-loop/<version>/`,
and **the cache is materialised only at session start**. In a running session the cache stays older than the
clone you just pulled: measured here as a 0.6.15 clone against a newest-cache of 0.6.8.

The old implementation listed candidates as "cache sorted `-V -r`, then marketplaces" and took **the first
hit**, assuming candidate order tracks version. It doesn't on this path. It now reads `plugin.json` from
every candidate and takes **the highest version** (compared with `sort -V`; an unreadable version is
treated as `0.0.0` and kept only as a last resort).

This is a single observation, but it is the kind a machine can catch, so it gets caught on the first one
(v0.6.14). Left alone, the session right after a version bump has executors silently reading old knowledge
and being told the new reference template does not exist.

Verified: cache 9.9.9 + marketplace 1.0.0 → 9.9.9; cache 0.6.8 only + marketplace 1.0.0 → 1.0.0;
no candidate → exit 1.

</details>

<details>
<summary><b>v0.6.15</b> — Split the files that get read every time into an index plus topics (fewer tokens, same words)</summary>

The answer to "can I cut token spend by writing everything in English" was **yes, but splitting wins**.
Japanese costs about 1.4x English for the same content, but `gotchas.md` was expensive because
**506 lines got read whole every time someone got stuck** — and translating it doesn't change that.
So the words are untouched; only the amount read went down.

| | Before | After |
|---|---|---|
| `knowledge/gotchas.md` | 506 lines / ~10,567 tok, read **whole** | index 927 tok + one topic (468–2,790) = **1,395–3,717** |
| `knowledge/mule-basics.md` | 124 lines / ~5,483 tok, read by **every executor** | index 817 tok + only the topics touched (255–1,030) |

An executor opening two topics (flow + munit): **5,483 → 2,106 (-62%)**.
Four topics (flow + db + munit + error-handling): **3,798 (-31%)**.
Looking a gotcha up at the median topic: **10,567 → 2,027 (-81%)**.

**The honest number too: opening all 10 basics topics costs 6,780 — 24% more than before**, because each
file needs its own source-marker legend. **Reading 7+ topics is a loss**, so the win depends on the
discipline, not the split: read the index, open only what you touch. That's why every reader was updated:
`agents/mule-executor.md` picks one row from the index table and opens one file;
`agents/mule-reviewer.md` names the three files behind the five traps it checks;
`template/CLAUDE.md` and `mule-tdd` state "do not read the directory whole";
`mule-munit` states that `gotchas/munit.md` + `basics/munit.md` are all it needs.

- `knowledge/gotchas/`, 9 files (build 10 items / config 3 / munit 12 / error-handling 6 / apikit-http 3 /
  db 6 / dataweave 3 / deploy 6 / api-manager 4). The index selects a topic **by symptom**
  (`Cannot coerce`, "properties get wiped"), not by topic name — someone who is stuck cannot pick a
  topic name reliably.
- `knowledge/basics/`, 10 files. `kind.md` (Batch / MCP / A2A) is now **readable in isolation**, so its
  caveat — this is `[S]` only, with no measurement behind it — lives inside the file, not just in the index.
- **Losslessness was verified mechanically**, not by eye: 363 + 83 body lines each appear exactly once
  across the topic files. These are hand-written records with dates and evidence; a dropped line would
  be unrecoverable and silent.
- `/mule-learn` now appends to `knowledge/gotchas/<topic>.md`, and **fixing the index count is part of
  the step**. An index that drifts from reality is worse than no index: readers conclude "no row matches"
  and never open the file, so the item you wrote is read by nobody (PR #2 left the count at 11).
- The index states that the two trees do **not** pair 1:1. The summary for `gotchas/apikit-http` lives in
  `basics/flow.md`, the one for `gotchas/api-manager` inside `basics/deploy.md`, and `basics/flow` /
  `naming` / `kind` have no gotchas counterpart yet (nothing measured). **No item is duplicated to
  manufacture a pair.**

`knowledge/gotchas.md` and `knowledge/mule-basics.md` remain as the index paths, so all 18 files that
referenced them still resolve.

</details>

<details>
<summary><b>v0.6.14</b> — "It only happened once" is not a reason to leave it unmechanized</summary>

v0.6.13 left the dispatcher-breaks-its-own-file-ownership failure as a prose rule, **justified by
"n=1, so `/mule-learn`'s two-occurrence rule says wait."** That was wrong: it had become a reason
not to fix something fixable. The policy changed.

**How many occurrences a promotion needs now depends on the destination, not the count.**

| Destination | Occurrences | Why |
|---|---|---|
| hook / script / template | **1** | Zero reading cost. Put it where it acts; more of them slows nobody |
| A prose rule (`CLAUDE.md`, a skill, a review point) | **2** | Reading cost. Grown from single incidents, it bloats and stops being read |

The original rule's worry was that rules pile up until `CLAUDE.md` goes unread. That worry applies
**only to prose**. Nobody reads a hook, so there is no cost to writing one after a single incident.
Wait for a second occurrence only when prose is the only option — and conversely, something seen
twice or more still becomes prose if no mechanism can catch it.

**And the deferred item is now mechanical: `scripts/wave-guard.sh` (a PreToolUse hook).**

When dispatching, the progress agent writes `path<TAB>goal id` lines to `.claude/wave-owned`. The
hook reads it and **denies the progress agent's own Edit / Write**. It is not a request but a key it
turns on itself — the party that broke the declaration was the one who made it, so a declaration
cannot be assumed to hold. Once every goal is integrated the file is removed, and only then do the
shared appends happen, in one pass.

Who gets blocked is decided by **git's own signal**, not by guessing at path shapes: a linked
worktree's `--git-dir` is `<repo>/.git/worktrees/<name>` and differs from `--git-common-dir`, while
in the main working tree they match. So **executors (worktrees) pass through and only the dispatcher
(main tree) is blocked** — verified to hold even when `.claude/wave-owned` is committed by mistake
and shows up inside the worktree. A forgotten declaration **expires after 12 hours**, because
leftovers from an aborted wave silently blocking every later write would itself be a new `loop-ops`.

The hook sees only Edit / Write; shell-side appends like `echo >> file` are not caught (judging that
from a command string produces too many false positives). `/mule-run`'s forbidden list covers those.

One trap hit while building it: **passing the python body as a heredoc consumes the hook's JSON on
stdin.** `json.load(sys.stdin)` read nothing and no deny ever fired. Read stdin into a file first,
then pass the path — the same shape `stop-guard.sh` uses.

Verified across 10 cases: relative path, absolute path, a deep cwd, an unlisted file passing through,
a worktree passing through, a declaration older than 12 hours being ignored, no declaration file,
outside git, **a mistakenly committed declaration still denying only in the main tree**, and the
worktree still passing through in that case.
</details>

<details>
<summary><b>v0.6.13</b> — Stop letting K filenames be chosen by hand (1 of the 2 open loop-ops rows)</summary>

After v0.6.12's reclassification made `loop-ops` the largest cluster at 10, the breakdown showed the
worktree base (v0.6.4/0.6.7), the initial commit (`/mule-init` 6b) and the double-logged ledger
(v0.6.5) were already handled — **two rows were still open**.

**First: the K-file number collision.** Parallel executors independently picked the same
`K-NNN.md` and collided on integration. Putting the goal id in the name was already documented in
some places, but **two conventions were running side by side inside the plugin**:

| Where | What it said |
|---|---|
| `template/CLAUDE.md` (loaded every session) | `K-NNN.md` ← the colliding form |
| `skills/mule-learn/SKILL.md` | `K-NNN.md` ← same |
| `agents/mule-executor.md`, `skills/mule-run/SKILL.md` | `K-<goal id>-<seq>.md` |

Real projects had drifted into **four** shapes (`K-001.md` / `K-009-1.md` / `K-T-001-1.md` /
`K-T-003-1.md`), and `K-001.md` existed in both projects. **Chosen by hand, these never converge.**

`scripts/k-new.sh` now decides the name:

```bash
bash scripts/k-new.sh T-003   # → knowledge/K-T-003-1.md (-2 if it exists)
bash scripts/k-new.sh learn   # → knowledge/K-learn-1.md  (for /mule-learn promotions)
```

The goal id in the name makes collisions **structurally impossible across goals**. Five documents
were unified onto the one convention and every `K-NNN.md` is gone. The K file's **contents had two
shapes too** (`mule-learn` wanted promotion target and counts; `executor` wanted the evidence command
and where you looked), so they are now one, with promotion target and counts marked as
`/mule-learn`-only.

**It prints a path and does not create the file.** An empty K file showing up in a diff would make
`/mule-run`'s "is a K file in the diff" check report "learning recorded" — a toothless check.

**The second row (the dispatcher breaking its own declared file ownership) stays a rule.**
`/mule-run`'s forbidden list now says the progress agent must not touch an append-type file it
assigned to a goal in the current wave, and that completion appends happen once, after every
parallel goal is integrated. **It is not enforced mechanically.** It has happened once, and
`/mule-learn`'s own rule is to promote only what occurs twice or more. Building machinery from a
single incident — without even knowing which file it was — grows the plumbing, and that is itself
how new `loop-ops` rows appear. A second occurrence will identify the file; that is when it becomes
a hook.
</details>

<details>
<summary><b>v0.6.12</b> — Reclassifying changed which cluster is first (recovering 13 uncategorized rows)</summary>

**18 of finance-api's 41 ledger rows sat outside the fixed vocabulary**: `uncategorized` 13,
`toothless-assertion` 4, `connector-usage` 1. `/mule-learn` step 0 exists to clear exactly this
every time, and had never been run. Invented values are counted as separate things, so those rows
were **recorded but not counted, and therefore never promoted**.

Each row still carried `vocabulary_gap` — the writer's note about which term they actually wanted —
so that drove the reclassification: `loop-ops` 6, `test-toothless` 5, `connector-behavior` 4,
`secret-leak` 1, and 2 that no existing term covers.

**The ranking changed.**

| | Before | After |
|---|---|---|
| First | `munit-coverage` 8 | **`loop-ops` 10** |
| `loop-ops` | 4 | 10 |
| Outside the vocabulary | 18 | 0 |

Six of those rows were the worktree base, the K-file collision, the ledger never being written, and
the dispatcher breaking its own file ownership — **all `loop-ops`, whose promotion target is a PR
against the plugin itself**. Skip step 0 and the largest cluster stays invisible while you conclude
"MUnit is next." That example is now written into step 0 so it can't be skipped.

**One new vocabulary term: `environment-fact`** — a fact about the connected system or driver that
only measurement reveals (which schema JDBC lands in, `getSQLState()` always returning null, what
type a TIMESTAMP arrives as). Nothing existing covers it, and the point is that **its promotion
target is not `gotchas.md`**: it holds only for this endpoint, so it belongs in
`context/environment/`. Carried into the plugin it would be a lie. The `vocabulary_gap` fields
proposed three names (`environment-fact` / `external-driver-quirk` / `environment-setup`); they were
merged into one, because too many terms stop being countable.

The category → destination table now also states where `environment-fact` and `loop-ops` go.

**Promoting the 5 `test-toothless` rows**: all five share one root ("read the result without
confirming the check ran"), so `mule-munit`'s "does your test have teeth" section gained a **third**
measurement — tampering with a line-number-pinned `sed` when the lines had shifted, so **not one
character of the tamper landed**, and green was nearly read as "no teeth." Tamper by content, not
line number, and print the tampered line before running.

The reclassified ledger lives in finance-api, with the previous value kept per row as
`category_was` and the reasoning as `category_reason`, so the work can be checked.
</details>

<details>
<summary><b>v0.6.11</b> — The same fingerprint six times: ship a template, not prose (mule-munit)</summary>

**17 of the ledger's 62 failures are MUnit** — the biggest cluster: missing `mock-when`, coverage
gaps, toothless assertions. **Seven of them are one fingerprint**: an APIkit routing flow
(`<method>:\<path>:<config>`) that the coverage check demands be `flow-ref`'d, which doesn't work
without attributes. The sixth entry states the reason outright:

> All six were solved the same way; the fingerprint recurs because there is no template in reference/.

The seventh (`test-toothless`) then indicts the workaround itself. Without attributes, `flow-ref`
NPEs into `global-error-handler`'s `ANY` branch (500), so asserting only that `vars.httpStatus` is
non-null satisfies coverage — **and verifies nothing about request-driven branching**. Seven tests
of that shape were left behind.

**Added `template/reference/router-test.xml`**: typed attributes, calling the routing flow directly,
**asserting the response body**. Three shapes — path variable, request body (mediaType in the flow
name), and the search case.

The typing method was proven on finance-api's main flow, but **nobody had ever run it against a
routing flow** (gotchas only asserted it was "the same problem"), so it was measured:
`get:\inventory\(inventoryId):inventory2-api-config` called with typed attributes, asserting
`payload.inventoryId` and `payload.warehouseCode` — **1 passed**. Break the expected value and it is
**Failed: 1 / exit 1**, so it has teeth. The weak substitute was never necessary.

The search exception is in the template too: when a routing flow's `queryParams` are all optional,
DataWeave's null propagation means it **completes normally** even without attributes, so the
"falls to 500" workaround does not hold at all (measured in T-003).

**`skills/mule-munit/` is deliberately thin.** gotchas.md is the primary record with evidence and
dates; the skill carries only the order to check things in and where the templates are: five
30-second pre-write checks, connector return shapes, what the coverage check does *not* look at,
**two measurements for whether a test has teeth** (break the expectation and see it fail; confirm the
intended case name appears as a failure — a preflight step failing first and exiting 1 without ever
running the intended check actually happened), and what MUnit cannot verify (transaction
commit/rollback, the SQL itself, listener serialization).

**`/mule-learn` gained topic skills as a promotion target.** This was the open design consequence
flagged last time: split gotchas by topic and new fingerprints have nowhere to land. There is now a
per-category table (`munit-*` / `test-toothless` → `skills/mule-munit/`) and a rule that **anything
solved the same way three or more times becomes a `template/reference/` template rather than prose**.
These six were exactly that.

Referenced from `mule-tdd`'s Red section and `agents/mule-executor.md`'s reading list, via the
`plugin-root.sh --skill` path added in v0.6.10.
</details>

<details>
<summary><b>v0.6.10</b> — The executor has no Skill tool: hand it paths, not skill names</summary>

`agents/mule-executor.md` said "first load `mule-tdd` **with the Skill tool**", while the same
file's `tools:` line reads `Read, Edit, Write, Bash, Grep, Glob` — **no Skill**. The harness's
resolved tool list doesn't show one either. The first instruction of the implementation loop was
impossible to follow. The policy stage's "first read the bundled official skills: `secure-api`,
`apply-policy-to-api-instance`" gave names with no paths, so they couldn't be followed either.

**And those three do not exist in this environment.** `scripts/setup-deps.sh` tries to install them
via `npx skills add mulesoft/mulesoft-dx`, but searching `~/.claude` finds none of `secure-api` /
`apply-policy-to-api-instance` / `build-mule-integration`. The executor was being told to read
things that aren't there — pure hunting time.

Three measurements about paths:

- `${CLAUDE_PLUGIN_ROOT}` **is expanded by the harness at load time**: in skill bodies it became
  `/home/…/.claude/plugins/cache/mule-loop-marketplace/mule-loop/0.6.7/`.
- But it is **not in the shell environment** (`env` has no such variable), so
  `cat $CLAUDE_PLUGIN_ROOT/...` always misses.
- **Reading a SKILL.md as a raw file gets no expansion.** An executor without the Skill tool reads
  the file directly, so `${CLAUDE_PLUGIN_ROOT}` arrives as literal text.
- The expansion target is a **version-scoped cache**, so a resolved absolute path written into the
  ledger stops working at the next version.

`scripts/plugin-root.sh` resolves all of it:

```bash
bash scripts/plugin-root.sh                       # plugin root (newest materialized version)
bash scripts/plugin-root.sh knowledge/gotchas.md  # a file inside the plugin
bash scripts/plugin-root.sh --skill secure-api    # a skill's SKILL.md, wherever it lives
```

Nothing found prints nothing and exits 1. The executor is told: "exit 1 means it isn't installed —
**stop there** and fall back to gotchas → `reference/mule-schema/INDEX.md` → the manual. **Do not go
hunting.**" `mule-tdd/SKILL.md` now opens with a note that a raw read leaves the variable
unexpanded, so it can resolve its own paths.

Whether `${CLAUDE_PLUGIN_ROOT}` is expanded in `agents/*.md` specifically is **unverified** (it needs
a live agent to check). The fix works either way: both branches are written out — use it if expanded,
run `plugin-root.sh` if it arrives literal.

Verified across 7 cases (newest-cache selection, a file inside the plugin, a bundled skill, an
uninstalled official skill → exit 1, a missing file → exit 1, an external skill under
`~/.claude/skills`, and a broken `CLAUDE_PLUGIN_ROOT`), plus an end-to-end walk in finance-api:
resolve the skill → read it raw → resolve the relative paths inside it.
</details>

<details>
<summary><b>v0.6.9</b> — Stop guessing connector element names: generate version-matched schema from the jars in ~/.m2</summary>

All 8 skills were loop mechanics; **none taught how to write a Mule app**. Domain knowledge was
`knowledge/mule-basics.md` (124 lines) plus `gotchas.md` (523 lines) and `template/reference/`,
delivered as "read basics every time, read gotchas when stuck." A goal that never touches a
database still read the database section, and being stuck on MUnit meant opening 523 lines of
which 45 of 52 entries were irrelevant — cost per goal rising with every addition.

First step: `scripts/schema-index.sh`. Connector XSDs and descriptions live in the jar's
`META-INF/` and differ per version, so **copying them by hand always drifts** — it breaks
gotchas.md's own "never guess a connector GAV" from the human side. Extracted from the jar, they
match the version the project actually resolved.

- The artifact list comes from `mvn -o dependency:list`. Regexing the pom drops `${...}` versions
  and transitive connectors (measured: 3 direct deps by regex vs. 99 resolved lines including
  `mule-sockets-connector`). Scope is not narrowed — `-DincludeScope=compile` **removes MUnit and
  the db connector**. It never touches the network.
- The runtime extension models are not dependencies (the runtime provides them), so they come from
  `<app.runtime>`, falling back to the newest same-major.minor in `~/.m2` (`minMuleVersion` 4.12.0
  vs. the 4.12.2 actually installed).
- Output goes to `reference/mule-schema/` and **is committed**: worktrees are cut from
  `origin/main`, so uncommitted files never reach the executor (v0.6.7). A side benefit is that a
  connector version change shows up in the diff. Measured at **21 files / 9,638 lines / 560 KB** —
  the versions this project uses, not everything.
- `INDEX.md` carries a table plus an operation list (`mockWhen`, `bulkInsert`, … taken from the
  jar), and the executor is told to **open one file, not all of them**. `mule-core-common.xsd` is
  3,503 lines and is never read top to bottom.

**No Node.** It ships by default on neither Windows nor macOS, and this plugin's existing baseline
is bash + python3 + jq. A jar is a zip, so `python3`'s `zipfile` reads it directly — zero new
dependencies.

Called from `/mule-init` step 5c (right after 5b populates `~/.m2`, before the 6b initial commit)
and from `preflight.sh` (regenerating only when `pom.xml` is newer than `INDEX.md`). **A failure
here never stops a wave** — the index makes things faster, but the foundation verdict belongs to
`mvn package`.

Verified on finance-api and inventory2-api, plus the failure paths: no `pom.xml` → exit 2,
unresolved dependencies → exit 2 with the recovery step, a version absent from `~/.m2` → falls back
within the same major.minor, and the `mule.schemas` collision across three jars → merged into one.
All 21 generated files pass `xmllint` (the GAV comment goes **after** the XML declaration; before
it, the file is not well-formed).
</details>

<details>
<summary><b>v0.6.8</b> — Deploy permission is written once in a file, not pressed every time</summary>

Every deploy asked a human twice. `template/.claude/settings.json` had `Bash(mvn * deploy*)`
under `ask`, so **every command** raised a prompt, and `mule-deploy`'s gate 2 demanded an
explicit instruction **in that conversation**, so every conversation needed it restated.
The permission was already written in `context/deployment/authorizations.yaml`; the two
prompts were confirming the same thing twice. Moving the judge from a human to a machine is
how the rest of this repo works, so leaving deploy on a human's Enter key was inconsistent.

`scripts/deploy-guard.sh` is now a PreToolUse hook. It catches `mvn ... deploy` /
`-DmuleDeploy` / `anypoint-cli ... deploy` and returns **allow with no prompt** when
`deploy.sandbox` is `allowed` and the environment name is not production-ish. It reads the
environment from `pom.xml`'s `<environment>` as well as `sandbox.yaml` — the pom is what
`mvn` actually uses, so a sandbox.yaml saying Sandbox does not save you if the pom points at
Production. Both empty is also a deny (an unverifiable target cannot be waved through).
The `mvn` / `anypoint-cli` deploy entries are gone from `ask`; the hook is the only decider.
Gate 2 became "a `stage: deploy` goal exists in the ledger" — the same never-work-outside-the-
ledger rule that already governs everything else. `template/CLAUDE.md` carried the old wording
too and was fixed; CLAUDE.md is loaded every session and outranks SKILL.md, so leaving it stale
would have kept the asking alive.

`authorizations.yaml` is located by walking up from the hook input's `cwd` to the git root.
Opening it by relative path would miss it whenever the working directory is not the project
root — monorepos, worktrees — and a miss is a **silent fall-through, i.e. an unguarded deploy**.
That is the same relative-path resolution accident v0.6.7 documents. If the command `cd`s to an
absolute path first (the shape `/mule-run` dispatches), that target is the starting point.
Nothing found by the git root means this is not a mule-loop repo, and the guard stays silent.

**The production guard got stronger, not weaker.** "Never point this at an environment named
Production" used to be a sentence in SKILL.md, enforced by the writer's attention. It is now a
hook returning deny, and the command does not run.

It catches `mvn mule:deploy` and `mvn deploy:deploy` as well as `mvn clean deploy`, and the
production test includes `prd` — a common Anypoint abbreviation that does not contain `prod`.

**Verified end-to-end.** In a real `--permission-mode default` session, a command containing a
`touch` that no allowlist covers ran **with no prompt** when `allowed`, and was **blocked with the
hook's reason** when `denied`. The script itself is covered by 17 cases (still-denied, non-deploy
commands passing through, the `deploy:` vs `policy:` same-key mix-up, a Production name, `PRD`, a
pom-only Production, an empty environment, `mvn mule:deploy`, anypoint-cli, a `cd` prefix, a deep
subdirectory walking up, and staying out of non-mule-loop repos).
</details>

<details>
<summary><b>v0.6.7</b> — A worktree is cut from origin/main, so nothing local reaches the executor</summary>

v0.6.4 claimed that committing before dispatch is what puts the goal file and the previous wave's output
into an executor's worktree. Three measurements say otherwise: the worktree is branched from **`origin/main`**
— not local HEAD, and not the current branch's upstream. (1) With one unpushed local commit, the worktree
sat on origin/main. (2) After pushing, it followed the *new* origin/main, so it isn't pinned at session
start. (3) Checked out on a feature branch whose upstream was pushed, it still used origin/main — so
branching doesn't help either. Pushing would, but the only reachable target is `main`, which is precisely
what gate 2 exists to protect. That block is rewritten rather than annotated: the pre-dispatch commit is a
checkpoint, and it makes nothing visible to a worktree.

Two changes follow. The dispatch prompt now carries the **goal's full text inline** plus the **absolute
project root**, with an instruction to `cd` there first — in a monorepo the worktree's working directory is
the repository root, not the project, which is how a relative `tasks/T-001.md` once resolved into a
different project and edited unrelated files. And isolation is now conditional: used when there is no remote
(**unverified** — nothing can be behind, but it hasn't been measured), or when `HEAD == origin/main` with a
clean tree; otherwise the goal is dispatched without isolation and run serially in the working tree. In
practice that means **isolation and parallelism apply to the first wave only**, since this wave's own
dispatch commit puts local ahead. The discriminator is deliberately not `blocked_by` — independent goals
share `pom.xml`, `global.xml` and the RAML, so they go stale the same way.

Also merges PR #5 (the APIkit gotcha now covers dispatch flows, not just the main flow) and fixes the
`MUnit` count in the gotchas index, which that PR left at 11.

</details>

<details>
<summary><b>v0.6.6</b> — One preflight instead of N executors failing the same way</summary>

When the shared ground is broken — dependencies won't resolve, the Exchange credentials are stale, a guessed
GAV doesn't exist, the pom was hand-edited — every executor in the wave hits it independently, burns its
three attempts (escalating to opus on the third), and the orchestrator learns nothing until all of them
return. The cost is N×3 runs for one root cause. `mule-run` now runs `scripts/preflight.sh` before each
wave and dispatches nothing if it fails: no goal is marked `running`, no `attempts` are incremented (the
ground failed, not the goal), a `build-config` line goes to `failures.jsonl`, and the raw output is handed
to the human.

The check is `mvn -q clean package -DskipTests` — the same command `mule-init` step 5b already validates a
new project with. It deliberately does **not** run MUnit: mid-loop, a failed goal's red test is sitting in
the tree by design, so `mvn test` would go red and halt every run at its first goal failure. That also
means preflight can't catch the failures that only appear when the embedded container boots (the 4.9.0 BOM,
mule-maven-plugin 4.7.0); `mule-init` 5b and `fix-plugin-version.sh` cover those at init time, and a
template-shipped canary MUnit is the follow-up if they start showing up mid-run.

Preflight runs **before** the wave is marked `running`, not after: the pickup filter is `todo`/`failed`, so
a goal stranded in `running` by a halt would never be dispatched again.

</details>

<details>
<summary><b>v0.6.5</b> — Why the learning loop never noticed the bug v0.6.4 fixed</summary>

The worktree defect had been recorded twice and still went unpromoted, so this release fixes the pipeline
rather than another fact. Four things were wrong. The vocabulary had no escape hatch, so the orchestrator
invented `uncategorized` — 13 times in finance-api — and an invented value aggregates as its own bucket
forever; `other` is now a defined category whose presence explicitly means the vocabulary is short. Step 1
counted by the `(category, symptom)` string pair, so one cause written two ways scored 1 and 1 instead of
2 — exactly what happened to the worktree entries ("the goal file wasn't there" / "the dependency's output
wasn't there") — so counting is now by cause. Nothing ever revisited old entries after the vocabulary grew,
which is why entries predating `loop-ops` stayed stranded; a new step 0 re-triages `other` on every run,
regardless of count, and mandates a re-read whenever the vocabulary is extended. And all three promotion
targets (`quick-check.sh`, `CLAUDE.md`, `mule-reviewer`) are repo-local, leaving `loop-ops` findings with
nowhere to go — that row now points at a PR against the plugin's own `skills/`/`hooks/`/`scripts/`, and
says a `gotchas.md` append does not fix a defect in a procedure.

The vocabulary lives in one file, but the agents that *write* the field are in others, so `mule-run` and
`mule-deploy` now state the fallback inline — that's the edit that actually reaches the writer.

</details>

<details>
<summary><b>v0.6.4</b> — Executors were being dispatched into worktrees that lacked their own goal file</summary>

`mule-run` committed exactly once, at the very end before opening the PR. Every `isolation: "worktree"`
executor is therefore branched from a HEAD that predates the entire run — and a git worktree does not carry
uncommitted changes. So an executor could start without **(a)** the `tasks/T-NNN.md` it was just handed, and
without **(b)** anything a dependency goal produced in an earlier wave (`pom.xml`, `global.xml`,
`knowledge/K-*.md`, config). That inverts the meaning of `blocked_by`: the goals most likely to break are
exactly the ones declaring a dependency. finance-api hit this twice, at T-011 and T-012, and both entries
sat in `failures.jsonl` uncategorised and unpromoted. `mule-run` now marks the whole wave `running` and
commits before dispatching it; `.gitignore` already excludes `target/` and `.claude/worktrees/`, so
`git add -A` stays safe.

Also promotes the last two deploy facts from the user's `mulesoft-app-development` skill that hadn't been
merged: reaching an RTF app from Flex Gateway needs a `type: LoadBalancer` Service whose EXTERNAL-IP goes
into the API instance's Implementation URI, and a Flex Gateway that refuses `curl` is usually resolving
`localhost` to `::1` — `curl -4` gets through.

</details>

<details>
<summary><b>v0.6.3</b> — The JDBC driver needs two entries in the pom, not one</summary>

v0.6.2 added a driver `<dependency>` fragment and claimed that was what stops `Cannot load driver class`.
It isn't. A JDBC driver is a plain jar rather than a `mule-plugin`, so the DB connector can't see it unless
it is *also* declared as a `<sharedLibrary>` under `mule-maven-plugin` — with the version omitted there,
present in the `<dependency>`. Miss the second entry and MUnit still passes, because `db:*` is mocked and
the driver is never loaded; it fails on the deployed runtime instead. finance-api's own pom has had this
since T-009, complete with a comment explaining it, but the finding never reached `knowledge/` or the
plugin — so every later project would have rediscovered it. `pom-fragments.xml` now carries both entries
and `mule-basics.md` §6 states the rule, tagged `[G]`.

</details>

<details>
<summary><b>v0.6.2</b> — Copyable patterns for HTTP request, DB operations, APIkit routing</summary>

An executor was observed unzipping the DB connector jar to work out an operation's XML shape — which is what
happens when `reference/` only covers the two DB operations finance-api happened to use (`db:update`,
`db:select`) and nothing at all for outbound HTTP. Adds `template/reference/patterns/` with `http-request.xml`
(request-config + auth, uri/query params, `responseTimeout`, `http:response-validator`, the `HTTP:*` error
types wired like `global.xml`'s DB branch, and the `mock-when processor="http:request"` MUnit shape) and
`db-operations.xml` (`db:insert`/`db:delete`, vendor connection elements, `db:pooling-profile`, the streaming
strategy that avoids the `foreach` + `db:update` deadlock, per-operation return shapes and their MUnit mocks).
`api-main.xml` gains three more APIkit flow stubs, since the generated flow name is the thing that silently
404s — the media-type segment appears for POST/PUT/PATCH but not for GET/DELETE.

`patterns/` is deliberately a **separate directory**: everything directly under `reference/` came out of a
build that actually passed, and that guarantee is the most useful property the skeleton has. The new material
is sourced from the user's own `mulesoft-app-development` skill (`[S]`), from measured facts already in
`mule-basics.md` (`[G][K]`), or from connector documentation (`[D]`), and anything recalled rather than
sourced is marked `【未確認】` with an instruction to confirm via `describe-connector` before copying it.
`pom-fragments.xml` gains the JDBC driver dependency that a DB app needs beyond the connector itself — with
placeholder coordinates rather than a version number, since the plugin's own rule is not to guess a GAV.
`mule-executor.md` points at one file per connector rather than the directory, and says to look here before
opening a jar.

</details>

<details>
<summary><b>v0.6.1</b> — Mule apps beyond HTTP APIs: batch, MCP servers, A2A</summary>

`/mule-init` used to open with a system/process/experience layer question, which only makes sense for an HTTP
API. It now asks `kind` first (`api` / `batch` / `mcp` / `a2a`), and only asks layer when `kind: api`. Picking
`a2a` stops `mule-init` immediately with a pointer to the `agent-network` and `deploy-agent-network-v1`/`v2`
skills instead of scaffolding a Maven/MUnit project that wouldn't fit (Agent Network is `agentNetwork.yaml` /
`.agent` files, not a Mule app). `mule-basics.md` gains a "10. Batch / MCP / A2A" section with the facts the
user's own `mulesoft-app-development` skill already had (no `<mcp:server>` element, one flow per
`mcp:tool-listener`, SSE testing; `blockSize`/`maxConcurrency` must stay unquoted numbers for batch), tagged
`[S]` since none of it has run through this loop yet. `quick-check.sh`'s System-layer connector check is now
scoped to `kind: api` (a `batch` app hitting a DB directly is normal) and defaults missing `kind:` to `api` so
every repo initialised before this version keeps behaving exactly as before. `mule-start`'s deploy/policy
auto-goals (`smoke-check.sh`/`policy-check.sh`) stay `kind: api`-only too, since both assume an HTTP base URL
that batch and MCP don't have. `mule-init`'s project-scaffolding step no longer hardcodes the HTTP connector
for every `kind` — it's `kind: api`-only now, `mcp` resolves its own connector GAV via `describe-connector`
instead of reusing the api default, and `batch` only pulls in the connectors it actually needs.

No action needed on already-initialised repos (e.g. finance-api): with no `kind:` line, the default keeps
every existing check behaving exactly as it did before this version.

</details>

<details>
<summary><b>v0.6.0</b> — Mule basics, a reference skeleton, and gotchas by topic</summary>

Two APIs took far too long because executors kept rediscovering Mule fundamentals. `knowledge/mule-basics.md`
distils them (project skeleton, properties, flow structure, error handling, DataWeave, DB connector, MUnit,
deployment; one fact per line, each with its source). `template/reference/` is a skeleton lifted from an API
that passed (global.xml with a problem+json error handler, APIkit main, a transactional impl flow, MUnit with
samples read via `readUrl`, dwl, config, pom fragments). `gotchas.md` is reorganised by topic, three duplicates
merged, ten entries added from the K files and the user's `mulesoft-app-development` skill. Executors, `mule-tdd`,
`mule-start` and the reviewer now read basics and reference before writing. Vocabulary: `test-toothless`, `secret-leak`.

</details>

<details>
<summary><b>v0.5.5</b> — PR #4 follow-ups, and how to look things up when stuck</summary>

Initial commit; K files named after the goal id; `target/` and worktrees ignored; `learned`
written to `failures.jsonl` on success too; `connector-behavior` and `loop-ops` added to the
vocabulary. Executors now look things up in the order **gotchas → skills → manual**, and
anything that stalled them even once goes into K. Fixed a `p()` false positive in
`quick-check`.

</details>

<details>
<summary><b>v0.5.4</b> — a requirements template, and data models decided with a human</summary>

Ships `context/requirements/_template.md`. The data model is never assumed: it is settled
through the up-front batch of questions and grilling (the System layer is mandatory).

</details>

<details>
<summary><b>v0.5.3</b> — collision handling for parallel intake, and a wall clock that counts working time</summary>

When parallel intake collides, exactly one goal is marked failed and redistributed. The
wall-clock ceiling counts **time the executor was actually running**, so waiting on a human
at a gate cannot blow the budget.

</details>

<details>
<summary><b>v0.5.2</b> — parallel by default</summary>

Goals that are ready are dispatched **in parallel by default** (`--parallel` is a flag that
turns it *down*, not up). `mule-run` may stop in exactly four places, and progress is reported
to the ledger rather than the conversation. Grounded in measurement — see *"9.67 hours for one
System API"* in `docs/methodology.md`.

</details>

<details>
<summary><b>v0.5.1</b> — PR #2 measurements folded into the procedure</summary>

Bump the version on every deploy (`bump-version.sh`); attach the CH2 public URL via the API
(`ch2-public-url.sh`); branch the policy procedure on gateway type (`api.gateway`); read the
vendored skills first.

</details>

<details>
<summary><b>v0.5.0</b> — everything downstream of implementation runs in the same loop</summary>

Deployment and policies become ledger goals (`stage:`) and go through the same loop. The
discipline — *don't work outside the ledger*, *don't read the manual first*, *close in three
blocks* — moved into `UserPromptSubmit` and `Stop` hooks so it does not fade over a long
conversation.

</details>

<details>
<summary><b>v0.4.1</b> — human input fixed to one batch plus four gates</summary>

Questions are confined to the first pass and four gates (`context/decisions.yaml`).
Intermediate decisions proceed on defaults and are listed as assumptions at approval.

</details>

<details>
<summary><b>v0.4.0</b> — the deploy loop</summary>

Adds `/mule-deploy`: after merge, deploy to Sandbox (CloudHub 2.0 / Runtime Fabric), verify
connectivity against the expectations in `samples/`, and feed failures back into the learning
loop. Previous release tag: `v0.3.2`.

</details>
