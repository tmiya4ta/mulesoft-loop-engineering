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
  mule-status/    Navigation: where you are, what's next
  platform-assistant/  MuleSoft's official meta-skill, vendored (Apache-2.0)
  mule-start/     Intent → plan → execute, end to end
  mule-run/       Plan and execute loops only (for resuming)
agents/
  mule-executor.md  Drives one goal until done_when passes (worktree-isolated)
  mule-reviewer.md  Read-only review
hooks/hooks.json  Before a deploy: scripts/deploy-guard.sh (reads authorizations.yaml, answers allow/deny)
                  Before an edit:  scripts/wave-guard.sh (keeps the dispatcher off files it assigned to a goal)
                  On every edit: scripts/quick-check.sh (seconds-long validation)
                  Every turn:    scripts/loop-reminder.sh (re-inject the discipline)
                  End of reply:  scripts/stop-guard.sh (bounce once if not closed in 3 blocks)
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
                  schema-index.sh (~/.m2 の jar からコネクタ定義と XSD を抜く),
                  plugin-root.sh (プラグインとスキルの場所をパスに解決する),
                  k-new.sh (K ファイルの名前を機械が決める)
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
<summary><b>v0.6.18</b> — Without git, four mechanisms silently become no-ops. Stop the wave in preflight</summary>

While redistributing the scripts to existing projects, **`inventory2-api` turned out not to be a git
repository**. It has `knowledge/`, it has `tasks/`, it has six goals of history. And yet:

- executor **worktree isolation** — cannot be created, so parallel goals share one tree
- **`wave-guard.sh`'s file-ownership split** — designed to pass through when git is absent (so it never
  misfires inside a worktree)
- the **"is a K file in the diff" check** — no diff, no answer
- **`/mule-learn --share` PRs** — promotions never get shared

All four were doing **nothing, with no error and no warning**. That is the opposite of everything else
here: `deploy-guard` returns a deny, `wave-guard` returns a deny, `coverage-check` returns exit 1.
**A check that silently does nothing is worse than no check** — you proceed believing it held.

`scripts/preflight.sh` now verifies git first and **exits 2, dispatching nothing**, if it is absent (the
same treatment as a missing `pom.xml`). The failure names all four mechanisms and prints the one-line
`git init` remedy, so nobody has to guess why the wave stopped.

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
