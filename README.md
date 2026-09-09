# mulesoft-loop-engineering

**Build MuleSoft APIs with Claude Code, through a loop instead of a chat.**

[English](README.md) · [日本語](README.ja.md)

This repository is the Claude Code plugin **`mule-loop`** and its project template. You
describe what the API should do; it carries that from specification → acceptance criteria →
a goal ledger → implementation → pull request, in one console. **You do not need to know
MuleSoft to start** — `/mule-start` asks what it needs to know.

Implementation is TDD throughout (Red → Green → Refactor). The reasoning behind the design is
in [docs/methodology.md](docs/methodology.md).

> **v0.6.6** — see [Release notes](#release-notes).

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
| **3** | Production deployment (Sandbox is handled by `/mule-deploy` given `authorizations.yaml` and an explicit instruction) |
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
  mule-deploy/    Deploy loop — Sandbox, verify with samples, failures back to learning
  mule-learn/     Learning loop — count failures, promote, share
  mule-status/    Navigation: where you are, what's next
  platform-assistant/  MuleSoft's official meta-skill, vendored (Apache-2.0)
  mule-start/     Intent → plan → execute, end to end
  mule-run/       Plan and execute loops only (for resuming)
agents/
  mule-executor.md  Drives one goal until done_when passes (worktree-isolated)
  mule-reviewer.md  Read-only review
hooks/hooks.json  On every edit: scripts/quick-check.sh (seconds-long validation)
                  Every turn:    scripts/loop-reminder.sh (re-inject the discipline)
                  End of reply:  scripts/stop-guard.sh (bounce once if not closed in 3 blocks)
knowledge/mule-basics.md  Mule basics distilled from two loops and the user's skill; executors read it before writing
knowledge/gotchas.md  Shared knowledge by topic, with evidence, read by every executor
template/reference/   Reference skeleton (global.xml / impl / MUnit / dwl / config) taken from an API that passed
template/         What /mule-init distributes:
  context/        Where premises live (requirements / environment / deployment) + sources.yaml
  budget.yaml     Cost ceilings, checked before /mule-run dispatches
  context/deployment/authorizations.yaml   Deploy + live-system permissions (written by a human)
  tasks/          The goal ledger (done_when + attempt log)
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh, preflight.sh,
                  munit-coverage-mode.sh, run-log.sh, metrics.sh, cost-report.sh
.mcp.json         MuleSoft DX MCP Server (stdio) + Platform MCP Server (http)
docs/methodology.md
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

---

## Release notes

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
