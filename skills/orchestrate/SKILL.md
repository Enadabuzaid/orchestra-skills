---
name: orchestrate
description: >-
  An AI engineering router that decides how much intelligence, context and money a coding task
  deserves. A cheap Haiku router classifies tiny / small / feature / complex BEFORE any expensive
  call; the Orchestra policy (ROLE → MODEL with ordered fallbacks, routing levels, token budget)
  decides the rest: tiny = one card to a builder plus a test; small = light plan + review; feature =
  one Fable plan, builders, independent reviewers, tests, one Opus audit; complex = adds a second
  opinion from another model family. Builders get minimum-sufficient-context cards, and retries send
  only the failing check. Use when the user says "orchestrate" or wants to save tokens on coding work.
license: MIT
metadata:
  author: Enad Abuzaid
  homepage: https://github.com/Enadabuzaid/orchestra-skills
  version: 0.5.0
  requires: amElnagdy/delegate-skills relays, a clone of orchestra-skills at ~/orchestra-skills
---

# Orchestrate

You are the **orchestrator**: you route, dispatch, check and commit. You never write the feature code
yourself when a role fits, and you run on a cheap model if you can (`/model sonnet`). Planning happens
in planner roles, not here.

## The tools you use

| Command | What it answers |
|---|---|
| `~/orchestra-skills/scripts/orchestra route <level>` | how much process this level gets (planning, reviews, final audit, coordinator) |
| `~/orchestra-skills/scripts/orchestra resolve <role> [--not-model m] [--not-family tool] [--cheap-only]` | which model does this role **right now** (first available in its chain), and the exact relay command |
| `~/orchestra-skills/scripts/orchestra budget start <run> --dir <runs-dir>` / `spend <run> <role> <model> [--note …]` | the token budget: record every call **before** making it. `spend` exits 3 (REFUSED) when the budget forbids it |
| `~/orchestra-skills/scripts/orchestra exhausted <tool> [--until HH:MM]` | mark a tool out of quota, so every role skips it |
| `~/orchestra-skills/scripts/orchestra metrics <run>` | run metrics for the final report |
| `~/orchestra-skills/scripts/brief-check.sh <card>` | minimum sufficient context: every card must pass before it's sent |

Roles, fallbacks and budget rules: [references/policy.md](references/policy.md). Card formats (task
card, delta retry, review card): [references/brief-template.md](references/brief-template.md).

Run folders: `${TMPDIR:-/tmp}/orchestrate/<repo>/<step>/`, never inside the repo. **Never end your
turn while a relay is running**; block with `until [ -f <dir>/result.json ]; do sleep 15; done`.

## 0. Route (before anything expensive)

1. `git status` must be clean (otherwise ask the user to commit or stash). Note the base commit.
2. Dispatch the `task-router` subagent with the request and the repo path. The user's override wins.
3. `orchestra route <ROUTE>` gives the level's policy. Use `run=<repo>-<date>-<slug>` and
   `orchestra budget start <run> --dir ${TMPDIR:-/tmp}/orchestrate/<repo>`.
4. Follow the level below **and nothing more**.

### tiny: no plan, no reviewer, no audit

One task card for the router's role (default `small`) → `orchestra resolve <role>` → `budget spend`
→ run the relay command with `--brief <card> --cd <repo> --out-dir <dir>` → run the gate (the tests
for that area) yourself → commit → report in two lines. A failure gets a **delta retry** (§3). If it
turns out to be more than one task, re-route as small.

### small: light plan, builder, one review, no final audit

`planner-light` writes a compact plan (≤ `max_tasks` tasks; more → re-route as feature) → build each
task (§3) with the policy's reviews → run the plan's Verify once → report.

### feature and complex

- **feature:** §1 plan (`planner`) → §3 build through the `lane-runner` → §4 final audit.
- **complex:** §1 plan (`planner`, or `planner_when_hard` if the router said `Hard: yes`) → §2 second
  opinion, **only if** the router's `Areas:` intersect `second_opinion.only_for` (architecture,
  security, payments, migrations) or `Hard: yes` → §3 build → §4 final audit.
- A plan with more tasks than the level's `max_tasks` moves the work up one level.

Older route names: simple = tiny, medium = feature, very-complex = complex with `Hard: yes`.

## 1. Plan (one expensive call)

1. `orchestra resolve <planner role>` → `orchestra budget spend <run> <role> <model>`. Refused → use
   `--cheap-only`.
2. Planner brief (read-only): the request, the router's `Files:`, "Repo: <path>. Base commit: <sha>.
   Read only what you need, then reply with ONLY the plan in markdown following this template:", and
   [references/plan-template.md](references/plan-template.md). Every task gets a **role** (backend,
   frontend, tests, refactor, debug, docs, small), files, rules, acceptance, a task gate, and
   `Sensitive` (yes/no). Plus Contracts, Definition of Done, Verify (the repo's real commands plus one
   runtime check), and Out of scope.
3. Save `finalMessage` to `docs/plans/<date>-<feature>.md` with `Planner: <model>` and `Run: <run>`
   under the title. Commit it. A quota failure → `orchestra exhausted <tool>`, then resolve again.

## 2. Second opinion (complex, and only when justified)

`orchestra resolve architecture --not-family <planner's tool>` → `budget spend` → a read-only brief:
`~/orchestra-skills/agents/plan-reviewer.md` below its front-matter + "Plan: <path>. Repo: <path>.
Reply APPROVE or CHANGES REQUIRED." `CHANGES REQUIRED` → **don't call the expensive planner again**
(the planning budget is 1). Apply the numbered fixes yourself or with `planner-light`, commit, and
record the verdict in the plan. Budget refused → skip the second opinion and say so.

## 3. Build: Planner ≠ Builder ≠ Reviewer

Tiny and small: you do this yourself. Feature and complex: dispatch the `lane-runner` subagent with
the plan path, repo, run id and task IDs, then read only its run report.

For each task:
1. **Card:** a task card ([references/brief-template.md](references/brief-template.md)) with only
   this task's facts. `brief-check.sh` must pass.
2. **Builder:** `orchestra resolve <task role>` → `budget spend` → the relay command. A quota,
   permission or availability failure → `orchestra exhausted <tool>` (quota) → resolve again (the
   next fallback) → `budget spend … --note "fallback from <model> (<reason>)"`.
3. **Gate:** run the task gate yourself. It fails → a **delta retry** in the same session
   (`--session <id>`): `Continue <ID>.` + only the failing check + expected/actual + already accepted
   (`budget spend … --note "retry"`). Up to `implementation.max_retries`; then one delta to `debug`,
   then the next fallback model.
4. **Reviews** (the level's `reviews`, read-only, **never the builder's model**): save
   `git diff -- <files>` to `…/<task>/review/diff.patch`, write a review card, then
   `orchestra resolve <review role> --not-model <builder model>` (add `--not-family <builder tool>`
   for `security-review` and Sensitive tasks). `review` runs for every task, `ui-review` for frontend
   tasks, `security-review` for Sensitive ones. Findings → a delta retry to the builder.
5. **Land:** the plan's test command, then commit only this task's files (plain message, no
   Co-Authored-By trailer), and mark the task done in the plan.

## 4. Final audit (feature and complex: one expensive call)

Record the call (`budget spend <run> final-audit <model>`), then dispatch the `completion-auditor`
subagent (Opus) with the plan, repo and base commit. It checks every plan item and runs the Verify
commands.
- `DONE` → §5.
- `GAPS` → build each gap as a task (§3). Then **re-verify deterministically**: run Verify and the
  `review` role on the gap diffs. Don't call Opus again unless the budget allows it
  (`final_audit.max_calls`).

## 5. Report

The route and why; `orchestra metrics <run>` (expensive calls used / budget, fallbacks, retries,
relay tokens); tasks → role → model → commit; review findings; each Verify command and its result;
manual checks for the user. Nothing is pushed.

## Hard rules

- Nothing expensive before the router. Every expensive call goes through `budget spend` first.
- Minimum sufficient context: cards only, checked by `brief-check.sh`. Retries are deltas.
- Planner ≠ builder ≠ reviewer. Reviews, planners and audits run read-only, and so do their fallbacks.
- Never add `--dangerously-skip-permissions` or `--allow-all-tools`, and never widen tool
  permissions without the user.
- Workers never orchestrate: if your input is a card or you were started by a relay, just do the card.
