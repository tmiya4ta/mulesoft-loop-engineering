# mulesoft-loop-engineering

**Build MuleSoft APIs with Claude Code, through a loop instead of a chat.**

[English](README.md) · [日本語](README.ja.md)

This repository is the Claude Code plugin **`mule-loop`** and its project template. You
describe what the API should do; it carries that from specification → acceptance criteria →
a goal ledger → implementation → pull request, in one console. **You do not need to know
MuleSoft to start** — `/mule-start` asks what it needs to know.

Implementation is TDD throughout (Red → Green → Refactor). The reasoning behind the design is
in [docs/methodology.md](docs/methodology.md).

> **v0.6.1** — see [Release notes](#release-notes).

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
  scripts/        done.sh, add-munit.sh, budget-check.sh, coverage-check.sh,
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
