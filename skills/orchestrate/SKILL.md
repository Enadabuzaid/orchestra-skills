---
name: orchestrate
description: >-
  Build features paying for big-model thinking only where it's needed: a cheap Haiku task-router
  picks simple / medium / complex / very-complex; the plan comes from a semantic `planner` lane (Fable
  by default, Opus for very hard work, with fallbacks); hard plans are challenged by a different AI
  (the architecture-review lane); a Sonnet lane-runner hands each task a tight task card and builds
  across job lanes (backend, frontend, tests, refactor, debug, docs, reviews); one Opus final audit decides DONE. Use when the user says "orchestrate" or wants to save
  tokens on feature work. Your session can run on Sonnet, because planning happens in the lane.
license: MIT
metadata:
  author: Enad Abuzaid
  homepage: https://github.com/Enadabuzaid/orchestra-skills
  version: 0.5.0
  requires: amElnagdy/delegate-skills (codex-delegate, agy-delegate, claude-delegate, copilot-delegate, delegate-setup)
---

# Orchestrate

You are the **orchestrator**. You think, gate, review and commit. You do **not** type implementation
code when a lane fits — implementers do, in their own sessions, on their own quota.

Token rule of thumb: **only the thinking that's needed gets paid for.** A cheap router picks the
route. Planning goes to the **`planner` lane** (Fable by default), not to this session, so this
session can run on a cheap model (`/model sonnet`). A **different AI** challenges hard plans, and the
Opus final audit runs once, repeating only if it finds gaps.

```
request → task-router (Haiku)
  simple        → one task card → lane → tests → commit
  medium        → planner (Fable)                          → build → final audit
  complex       → planner (Fable) → architecture-review (Astra)     → build → final audit
  very-complex  → planner-hard (Opus) → architecture-review (Astra) → build → final audit
```

| Role | Default model | Where |
|---|---|---|
| Route the request | Haiku | `task-router` subagent |
| Plan | Fable (primary), Opus (fallback / very hard), Astra (alternate) | `planner`, `planner-hard`, `planner-fallback`, `planner-alt` lanes |
| Challenge the plan (complex+) | **a different model family** from the planner | `architecture-review` (or `architecture-review-alt` when the first is the planner's family) |
| Build | job lanes: backend, frontend, tests, refactor, debug, docs, small | your lane config |
| Reviews per task | `code-review` (every task), `ui-review` (frontend), `security-review` (sensitive) | `lane-runner` |
| Coordination, gates, commits | Sonnet | `lane-runner` subagent |
| Final audit (once; repeats only on gaps) | Opus | `completion-auditor` subagent |

**Lanes are jobs, not vendors.** The vocabulary, the older names that still work, and the rules
for reviews, debug and fallbacks are all in [references/lanes.md](references/lanes.md). Resolve a
job with `~/orchestra-skills/scripts/lanes.sh resolve <job>`, and never name a vendor in a plan or
brief.

**Context isolation is the main token saver.** Every implementer, reviewer and checker gets one
task card ([references/brief-template.md](references/brief-template.md)), checked by
`~/orchestra-skills/scripts/brief-check.sh`: never the conversation, the plan discussion, old
attempts, or whole files.

**Fallbacks, for every lane:** when a lane fails because of quota, permissions or availability,
use `<lane>-fallback` if it exists, then the global `fallback` lane. For planners the chain is
`planner` → `planner-fallback` → `planner-alt`. Always tell the user which one actually ran.

## Stage 0 — Route (cheap)

Dispatch the `task-router` subagent with the user's request and the repo path. Follow its `ROUTE`,
unless the user named one ("treat this as very complex"): the user always wins.

- **simple**: no plan file and no gates. Dispatch the `lane-runner` with: "Simple task, no plan. Write
  one brief for: <request>. Lane: <router's lane, default `small`>. Gate: <the repo's test command
  for the touched area>. Land it as one commit." Report what it returns. Done.
- **medium**: Stage 1 with `planner` → **skip Stage 2** → Stages 3–6 → Stage 7.
- **complex**: Stage 1 with `planner` → Stage 2 → Stages 3–6 → Stage 7.
- **very-complex**: Stage 1 with `planner-hard` (if it's missing, `planner`) → Stage 2 → Stages 3–6 → Stage 7.

## Stage 1 — Plan (the planner lane)

One planner produces the architecture. It runs **read-only** and returns the plan as text; you save it.

1. `git status` must be clean (otherwise ask the user to commit or stash). Record the base commit.
2. Write the planner brief to `${TMPDIR:-/tmp}/orchestrate/<repo>/plan/brief.md`:
   - the user's request and the router's notes (files, lanes);
   - "Repo: <abs path>. Base commit: <sha>. Explore the code read-only, then reply with ONLY the
     complete plan in markdown, following this template:" and the full text of
     [references/plan-template.md](references/plan-template.md);
   - the plan must contain **Tasks** (each small enough for one brief: goal, files, acceptance
     tests, task gate, **job lane** from references/lanes.md (`backend`, `frontend`, `tests`,
     `refactor`, `debug`, `docs`, `small`), `Sensitive: yes` on tasks touching auth, payments,
     permissions, uploads or crypto, dependencies, a `Status` column), **Contracts** shared between tasks, a **Definition of Done**
     made of user-visible outcomes, and **Verify**: the repo's real commands (full tests, static
     analysis, format check, build) plus at least one runtime check, with `manual` for anything
     that needs a human.
3. Run it (read-only), blocking until `result.json` exists:
   `node ~/.claude/skills/<lane's tool>-delegate/scripts/relay.mjs --lane <planner lane> --read-only --brief <brief> --cd <repo> --out-dir <run>/plan/<lane> --timeout 45m`
   (prefix `env -u ANTHROPIC_API_KEY` when the tool is `claude`). If it fails because of quota,
   permissions or availability, go down the chain: `planner-fallback`, then `planner-alt`.
4. Save `finalMessage` to `docs/plans/<YYYY-MM-DD>-<feature>.md`, and add `Planner: <lane> (<tool>
   <model>)` under the title. Check that Tasks, Definition of Done and Verify are present; if not,
   send one delta brief to the same session (`--session <id>`). Commit the plan.
5. **No planner lane configured?** Plan in this session instead (use `/model fable` or `opus` for
   that), and say so.

## Stage 2 — Challenge the plan with a different AI (complex and very-complex)

Skip for medium. The challenger must be a **different model family** from the planner that actually ran:

Use `architecture-review`, unless its tool is the same family as the planner that actually ran;
then use `architecture-review-alt` (`lanes.sh resolve` accepts the older names `plan-check` and
`plan-gate`).

1. Write a brief to `<run>/architecture-review/round-N/brief.md`: the text of
   `~/orchestra-skills/agents/plan-reviewer.md` **below its front-matter**, plus "Plan file: <abs
   path>. Repo: <abs path>. Review the plan against the real code. Reply APPROVE or CHANGES REQUIRED
   in the exact format above."
2. Run it read-only on the challenger lane with the relay, and block until `result.json` exists.
3. `APPROVE` → continue. `CHANGES REQUIRED` → send the planner a delta brief with the numbered
   fixes (`--session <id>` from its result), save the revised plan, commit it, and challenge again
   (max 3 rounds; then show the user the remaining disagreements).

**Fallback:** if neither challenger lane is a different family from the planner, or it or fails because
of quota, permissions or availability, dispatch the `plan-reviewer` subagent (Opus) instead, and say
which checker was used.

Never dispatch implementation before the plan is approved (complex+) or saved (medium).

## Stages 3–6 — Hand the plan to the `lane-runner` (Sonnet)

Coordination (writing briefs, running relays, waiting, reviewing diffs, committing) is routine,
and it is where most orchestrator tokens go. **Don't do it on Opus.** Once the plan is approved:

1. Commit the approved plan.
2. Dispatch the `lane-runner` subagent (Sonnet) with the plan path, the repo path, and the task IDs
   to run (all of them, in plan order). Wait for its `RUN REPORT`. Don't end your turn before
   it arrives.
3. Read only the report. Check it with cheap commands: `git log --oneline <base>..HEAD`,
   `git status`, and the full test command. Don't re-read the diffs; the completion auditor does
   that next.
4. Tasks reported as "not done" → decide: fix the plan (and send it back through `plan-reviewer` if
   the design changes), re-run the `lane-runner` for those tasks, or escalate to the user.

The sections below describe what the `lane-runner` does. Follow them yourself only if you're
running without it (for example, the user asked you to drive the lanes directly).

## Stage 3 — Briefs

One brief per task, written with [references/brief-template.md](references/brief-template.md).
Briefs are self-contained: paths and facts, never chat history. Keep each under ~1 page.

## Stage 4 — Dispatch to lanes

Load the matching delegate skill and run its relay with `--lane`:

Lanes live in `~/.config/delegate-skills/config.json` and **the user can change them**, so always
read the current map (`node ~/.claude/skills/delegate-setup/scripts/config.mjs load`) instead of
assuming one. Default meaning of each lane name:

The job lanes and their rules are in [references/lanes.md](references/lanes.md).

```bash
node "<delegate-skill-dir>/scripts/relay.mjs" --lane backend --brief brief.md --cd "$REPO"
```

- Always pass `--out-dir "${TMPDIR:-/tmp}/orchestrate/<repo-name>/<task-id>"` so you know where
  `result.json` will land. Keep it **outside the repo**, so run logs never end up in the working tree.
- Start the run with `run_in_background: true`, then **never end your turn while a run is in
  flight.** If you have nothing else to do, block on it in the foreground:
  `until [ -f <dir>/result.json ]; do sleep 10; done` (Bash timeout 600000), repeated until it exists.
  In a headless session (`claude -p`, CI, scripts), ending your reply ends the process and kills
  every running implementer (the relay reports `aborted … SIGTERM`).
- Independent tasks touching **disjoint files** may run in parallel. Tasks touching the same files
  run sequentially.
- Follow-ups go to the same session with a delta brief (`--session <id>` from `result.json`).

## Stage 5 — Review each diff (cheap first)

The `lane-runner` reviews each diff itself. When you drive the lanes yourself, dispatch the
`diff-reviewer` subagent (Sonnet) with: the brief path, the task's touched files, and the
repo's gate commands. It returns `PASS` or `FAIL` with findings.

- `FAIL` → delta brief to the same implementer session. After two failed rounds, reroute to `fallback`
  or fix it yourself if it's tiny.
- `PASS` → you read only the reviewer's summary plus any hunk it flags as risky (auth, money, data
  migrations, deletes, security). Do not re-read the whole diff.

## Stage 6 — Land

Re-run the gates yourself (never trust a self-report), then commit with a conventional message.
Implementers never commit. Set the task's `Status` to `done` in the plan in the same commit, so the
plan is always the source of truth for progress.

Don't start Stage 7 while any task is still `todo`.

## Stage 7 — Final audit (Opus, once; repeats only on gaps)

Implementation being finished doesn't mean the feature is finished. Dispatch the
`completion-auditor` subagent (Opus) with the plan path, the repo path, and the base commit. It
checks every task and every **Definition of Done** item against the code, runs every **Verify**
command, checks that tasks from different implementers fit together, and looks for leftovers.

- `DONE` → go to Stage 8.
- `GAPS` → each gap becomes a new task. Add it to the plan's task table as `G1`, `G2`, … (`todo`),
  with the lane the auditor suggested, commit the plan, and dispatch the `lane-runner` with just
  those IDs. Then run `completion-auditor` again.
- Maximum 3 rounds. If there are still gaps after round 3, stop and show the user the remaining gaps
  with the auditor's evidence. Never report the feature as finished while the auditor says `GAPS`.

For large or risky features, you may also send the final diff to the read-only `architecture-review` lane
(GPT-6 Astra) for a second opinion. Feed real findings back into the loop.

## Stage 8 — Report to the user

Only after `DONE`. Keep it short and factual:

- what was built (one line per task, with its commit hash and implementer);
- the verification results: each **Verify** command and whether it passed, with the auditor's output
  as evidence;
- what the gates caught along the way (plan-review rounds, `FAIL`s, gaps fixed);
- anything the user still needs to do or check by hand (the auditor's `manual` items, and pushing).

## Hard rules

- Every brief carries the repo's forbidden commands (see template). Default: no `composer update`,
  no `npm update`, no migrations against real databases, no `git push`, no commits.
- If the repo has no git history or safety net, say so in every brief and forbid wide-reaching commands.
- Report outcomes faithfully: a lane that failed is reported as failed, with its `result.json` status.
- Parallel tasks share one working tree: give each task its **own** test file as its gate and run
  the full suite only after they have all landed.
- A lane on Antigravity failing with *write_file permission auto-denied* → Antigravity needs a scoped rule for
  that folder: `~/orchestra-skills/scripts/agy-allow.sh <repo> --tests "<test cmd>"`. Never switch
  to `--dangerously-skip-permissions` without the human's explicit yes.
- A lane that reports a quota or rate limit (402/429) → send the task to `fallback` and tell the user.
