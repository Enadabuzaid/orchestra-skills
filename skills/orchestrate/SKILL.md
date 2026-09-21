---
name: orchestrate
description: >-
  Build a multi-task feature with expensive models only for thinking and cheap models for the
  rest: plan with Fable/Opus, gate the plan through an Opus plan-reviewer until APPROVE, hand the
  approved plan to a Sonnet lane-runner (it writes briefs, sends them to delegate-skills lanes:
  complex/backend=codex, ui=agy, small/fallback=claude sonnet, reviews diffs, and commits), then loop an Opus
  completion-auditor (plan checklist + verify commands) until DONE. Use when the user says
  "orchestrate", "plan and delegate", "big model plans, cheap model builds", or wants to save tokens
  on a multi-task feature. DO NOT USE for a one-file change you can make inline faster than writing a brief.
license: MIT
metadata:
  author: Enad Abuzaid
  homepage: https://github.com/Enadabuzaid/orchestra-skills
  version: 0.2.0
  requires: amElnagdy/delegate-skills (codex-delegate, agy-delegate, claude-delegate, copilot-delegate, delegate-setup)
---

# Orchestrate

You are the **orchestrator**. You think, gate, review and commit. You do **not** type implementation
code when a lane fits — implementers do, in their own sessions, on their own quota.

Token rule of thumb: the big thinkers (Fable, Opus, GPT-6 Astra) run ~3–4 times per feature (plan,
plan gate, optional second opinion, final audit). Everything line-by-line runs on a cheaper model.

| Role | Model | Where |
|---|---|---|
| Plan | Fable 5.1 or Opus 5 | this session, or the `Plan` agent with `model: "fable"` |
| Plan gate | Opus 5 | `plan-reviewer` subagent |
| Second opinion (optional) | GPT-6 Astra | `plan-check` lane, read-only |
| Large / complicated tasks | GPT-6 Astra | `complex` lane |
| Normal tasks | Codex default, Gemini Flash, Sonnet | `backend`, `ui`, `small` lanes |
| Stages 3–6: briefs, dispatch, diff review, commits | Sonnet 5 | `lane-runner` subagent |
| Completion check (loops until DONE) | Opus 5 | `completion-auditor` subagent |

## Stage 1 — Plan (big model)

- If the current session model is Fable or Opus, plan here. Otherwise dispatch the `Plan` agent with
  `model: "fable"` (or `"opus"`) and give it the requirements plus relevant file paths.
- Write the plan to a file (`docs/plans/<date>-<feature>.md` in the repo, or the plan-mode file).
- Record the **base commit** (`git rev-parse HEAD`) at the top of the plan. The final audit diffs from it.
- Use [references/plan-template.md](references/plan-template.md). The plan must contain:
  - **Tasks**, each small enough for one brief: goal, files, acceptance tests, lane
    (`complex` / `backend` / `ui` / `small`), dependencies, and a `Status` column (`todo` / `done`).
  - **Definition of Done**: a checklist of user-visible outcomes, not just "tests pass". For example:
    "admin can deactivate a provider from the list page", "a deactivated provider can't log in".
  - **Verify**: the exact commands that prove it works: the full test suite, static analysis, the
    formatter check, the build, and at least one runtime check (curl a route, an artisan command,
    or a script that exercises the feature). Mark anything that needs a human (for example a
    browser check) as `manual`.

## Stage 2 — Plan gate (Opus recheck, mandatory)

Dispatch the `plan-reviewer` subagent with the plan file path and the repo path.

- `APPROVE` → continue.
- Numbered fixes → revise the plan, re-dispatch. Loop until `APPROVE` (max 3 rounds; after that,
  show the remaining disagreements to the user and let them decide).

**Optional second opinion (GPT-6 Astra)** — for large or risky features, after Opus approves, send the
plan to the read-only `plan-check` lane (`codex-delegate --lane plan-check`) with the brief: "Review
this plan for gaps, wrong assumptions about the code, and risky ordering. Reply APPROVE or a numbered
list of fixes." A different model family catches different mistakes. If it raises real issues, fix
the plan and send it back through `plan-reviewer`.

Never dispatch implementation before `APPROVE`.

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

| Lane | Skill | Typical work |
|---|---|---|
| `complex` | `codex-delegate` (GPT-6 Astra, high) | large or tricky tasks: cross-cutting refactors, hard algorithms, concurrency |
| `backend` | `codex-delegate` | server code, actions, migrations, jobs, tests |
| `ui` | `agy-delegate` | React/TSX pages, components, styling |
| `small` | `claude-delegate` (Sonnet) | small fixes, lint/static-analysis fixes, text |
| `fallback` | `claude-delegate` (Sonnet, high) | when a lane fails twice or hits a quota limit |
| `copilot-review` | `copilot-delegate` (read-only) | optional third opinion on a plan or diff (writes need `--allow-all-tools`, full access — ask the human first) |

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

## Stage 7 — Completion loop (Opus decides when it's finished)

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

For large or risky features, you may also send the final diff to the read-only `plan-check` lane
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
- `ui` lane failing with *write_file permission auto-denied* → Antigravity needs a scoped rule for
  that folder: `~/orchestra-skills/scripts/agy-allow.sh <repo> --tests "<test cmd>"`. Never switch
  to `--dangerously-skip-permissions` without the human's explicit yes.
- A lane that reports a quota or rate limit (402/429) → send the task to `fallback` and tell the user.
