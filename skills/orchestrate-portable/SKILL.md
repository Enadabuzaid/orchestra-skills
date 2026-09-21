---
name: orchestrate-portable
description: >-
  The orchestrate workflow for apps without Claude Code subagents (Codex app/CLI, Cursor, …): your
  session's model plans (e.g. GPT-6 Astra in Codex), the plan is checked by Claude through the
  read-only `plan-gate` lane (e.g. Fable), tasks are built by your delegate-skills lanes (backend,
  ui, …), and a read-only `done-gate` lane (e.g. Opus) confirms every plan item before the feature
  counts as finished. Use when the user says "orchestrate" in Codex or another non-Claude-Code app.
  In Claude Code, use the `orchestrate` skill instead.
license: MIT
metadata:
  author: Enad Abuzaid
  homepage: https://github.com/Enadabuzaid/orchestra-skills
  version: 0.4.0
  requires: amElnagdy/delegate-skills (claude-delegate, codex-delegate, agy-delegate, delegate-setup), a clone of orchestra-skills at ~/orchestra-skills
---

# Orchestrate (portable)

You are the **orchestrator**. You plan, run the gates, dispatch, review and commit. Coding is done by
the lanes; the two quality gates are done by **Claude, read-only**, through the `claude-delegate`
relay. You never skip a gate and never commit before the task's gate commands pass.

Paths used below:

- `RELAY(<tool>)` = `~/.claude/skills/<tool>-delegate/scripts/relay.mjs` (or the same path under
  `~/.codex/skills/` / `~/.agents/skills/`, whichever exists).
- `LANES` = `node ~/.claude/skills/delegate-setup/scripts/config.mjs load`: the user's lane map.
  Read it once at the start. **Never assume which tool a lane uses.**
- `REF` = `~/orchestra-skills/skills/orchestrate/references` (plan and brief templates).
- `AGENTS` = `~/orchestra-skills/agents` (the gate instructions).
- Run dirs: `${TMPDIR:-/tmp}/orchestrate/<repo-name>/<step>/`, **never inside the repo**.
- For every relay whose tool is `claude`, prefix the command with `env -u ANTHROPIC_API_KEY`, so it
  uses the user's Claude subscription.
- **Never end your turn while a relay is running.** Block until `result.json` exists:
  `until [ -f <dir>/result.json ]; do sleep 15; done`.

## Gate lanes

| Lane | Default if missing | Job |
|---|---|---|
| `plan-gate` | `claude`, model `opus`, readOnly | approves the plan |
| `done-gate` | `claude`, model `opus`, readOnly | decides DONE / GAPS |

The user sets them with `lanes set plan-gate claude model=fable readonly` and so on. If a lane
is missing, pass `--model opus --read-only` explicitly.

## Stage 1: Plan (your session's model)

1. `git status`. If there's uncommitted work, stop and ask the user to commit or stash it first.
2. Record the base commit: `git rev-parse --short HEAD`.
3. Read the code the feature touches. Write `docs/plans/<YYYY-MM-DD>-<feature>.md` following
   `REF/plan-template.md`: Tasks (lane, files, acceptance tests, task gate, status), Contracts,
   **Definition of Done**, **Verify** (the repo's real test, lint, static-analysis and build
   commands, plus one runtime check), Out of scope. Use lanes that exist in `LANES` (for example
   `backend`, `ui`).
4. Run the baseline: execute the Verify commands once and note in the plan which ones already fail
   before any change.

## Stage 2: Plan gate (Claude, read-only)

Write a brief to `<run>/plan-gate/brief.md` containing:
- the full text of `AGENTS/plan-reviewer.md` **below its front-matter** (these are the reviewer's
  instructions);
- "Plan file: <abs path>. Repo: <abs path>. Review the plan against the real code and return
  APPROVE or CHANGES REQUIRED in the exact format above."

Run it:

```bash
env -u ANTHROPIC_API_KEY node RELAY(claude) --lane plan-gate --read-only --brief <brief> --cd <repo> --out-dir <run>/plan-gate/round-N --timeout 30m
```

Read `finalMessage` from `result.json`.
- `APPROVE` → set the plan's Status to approved and commit the plan.
- `CHANGES REQUIRED` → fix the plan and run round N+1. After 3 rounds, show the user what is still
  disputed and let them decide.

**No implementation before APPROVE.**

## Stages 3–6: Build each task

For each task, in plan order; tasks with disjoint files may run in parallel as `relayA & relayB & wait`:

1. **Brief** from `REF/brief-template.md`: goal, files, contracts, acceptance tests, the task gate,
   and Do NOT (no commits, pushes, dependency installs or updates, or files outside the task).
2. **Dispatch:** `node RELAY(<lane's tool>) --lane <lane> --brief <brief> --cd <repo> --out-dir <run>/<task>/run --timeout 45m`.
3. **Result:** `status` is not `completed` because of quota, permission or `*_unavailable` →
   re-dispatch once to `fallback`. Never add `--dangerously-skip-permissions` or `--allow-all-tools`.
4. **Review** it yourself with `git diff`: only allowed files touched, the acceptance tests exist,
   the task gate passes. On a problem, send a delta brief with `--session <id>` (max 2 rounds), then
   fall back.
5. **Check lane:** if `LANES` has `<lane>-check`, send it a read-only review brief of the diff and
   treat real findings as in step 4. The check is advisory.
6. **Land:** run the plan's test command, then commit only this task's files and set Status to done
   in the plan, in the same commit. Plain conventional message, no Co-Authored-By trailer.

## Stage 7: Done gate (Claude, read-only), looped

A read-only Claude can't run commands, so **you run the checks and hand over the evidence**:

1. Run every **Verify** command, and save the commands with their full output to
   `<run>/done-gate/round-N/verify.txt`. Also save `git log --oneline <base>..HEAD` plus
   `git diff <base>..HEAD` to `<run>/done-gate/round-N/diff.patch`, and `git status --porcelain` to
   `status.txt`. The gate can read files outside the repo (tested) but can't run `git`.
2. Write the brief: the text of `AGENTS/completion-auditor.md` below its front-matter, plus:
   "Plan: <abs path>. Repo: <abs path>. Base commit: <base>. You cannot run commands: the Verify
   commands were run for you (full output in <verify.txt>), the feature diff and commits are in
   <diff.patch>, and the working-tree status is in <status.txt>. Read and judge all three. Inspect `git`-tracked files directly for everything else. Return DONE or GAPS in the exact
   format."
3. `env -u ANTHROPIC_API_KEY node RELAY(claude) --lane done-gate --read-only --brief <brief> --cd <repo> --out-dir <run>/done-gate/round-N --timeout 30m`
4. `DONE` → Stage 8. `GAPS` → add `G1`, `G2`, … to the plan's task table (lane as suggested) and
   build them as in Stages 3–6, then run round N+1. After 3 rounds, stop and show the user the gaps.

**Never tell the user the feature is finished without the done-gate's `DONE`.**

## Stage 8: Report

Tasks → lane/tool → commit; each Verify command and its result; what the gates caught; the manual
checks left for the user; and `~/orchestra-skills/scripts/token-report.sh <repo-name>` output.
Nothing is pushed.
