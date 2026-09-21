---
name: orchestrate
description: >-
  Run a feature end-to-end with expensive models only for thinking and cheap implementers for
  typing: plan with Fable/Opus, gate the plan through an Opus plan-reviewer until APPROVE, split it
  into self-contained briefs, dispatch each brief to a delegate-skills lane (complex=codex astra,
  backend=codex, ui=agy, small=claude sonnet, fallback=claude sonnet), review each diff with a
  Sonnet diff-reviewer, land commits yourself, then run one final Opus audit. Use when the user says "orchestrate",
  "plan and delegate", "big model plans, cheap model builds", or wants to save tokens on a
  multi-task feature. DO NOT USE for a one-file change you can make inline faster than writing a brief.
license: MIT
metadata:
  version: 0.1.0
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
| Diff review | Sonnet 5 | `diff-reviewer` subagent |
| Final audit | Opus 5 | subagent with `model: "opus"` |

## Stage 1 — Plan (big model)

- If the current session model is Fable or Opus, plan here. Otherwise dispatch the `Plan` agent with
  `model: "fable"` (or `"opus"`) and give it the requirements plus relevant file paths.
- Write the plan to a file (`docs/plans/<date>-<feature>.md` in the repo, or the plan-mode file).
- The plan must list **tasks**, each small enough for one brief: goal, files to touch, acceptance
  tests, lane (`complex` / `backend` / `ui` / `small`), and dependencies between tasks.

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

- Run it with `run_in_background: true`; you are notified when `result.json` is written.
- Independent tasks touching **disjoint files** may run in parallel. Tasks touching the same files
  run sequentially.
- Follow-ups go to the same session with a delta brief (`--session <id>` from `result.json`).

## Stage 5 — Review each diff (cheap first)

Dispatch the `diff-reviewer` subagent (Sonnet) with: the brief path, the task's touched files, and the
repo's gate commands. It returns `PASS` or `FAIL` with findings.

- `FAIL` → delta brief to the same implementer session. After two failed rounds, reroute to `fallback`
  or fix it yourself if it's tiny.
- `PASS` → you read only the reviewer's summary plus any hunk it flags as risky (auth, money, data
  migrations, deletes, security). Do not re-read the whole diff.

## Stage 6 — Land

Re-run the gates yourself (never trust a self-report), then commit with a conventional message.
Implementers never commit.

## Stage 7 — Final audit (Opus, once)

Dispatch a subagent with `model: "opus"` over the whole branch diff vs the approved plan: missing
tasks, cross-task integration bugs, DB-portability issues (e.g. tests on SQLite but prod on Postgres),
security. Fix findings through the `small` lane.

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
