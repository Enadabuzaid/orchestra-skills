---
name: orchestrate-portable
description: >-
  The Orchestra workflow for apps without Claude Code subagents (Codex app/CLI, Cursor, …). Route
  first (tiny / small / feature / complex); the Orchestra policy decides planning, second opinion,
  reviews, final audit and budget; roles resolve to the first available model (ROLE → MODEL with
  fallbacks); builders get minimum-sufficient-context cards and retries send only the failing
  check; planner ≠ builder ≠ reviewer. Use when the user says "orchestrate" in Codex or another
  non-Claude-Code app. In Claude Code, use the `orchestrate` skill instead.
license: MIT
metadata:
  author: Enad Abuzaid
  homepage: https://github.com/Enadabuzaid/orchestra-skills
  version: 0.5.0
  requires: amElnagdy/delegate-skills relays, a clone of orchestra-skills at ~/orchestra-skills
---

# Orchestrate (portable)

You are the **orchestrator and the coordinator**: you route, dispatch, check and commit, at every
level. Planning, building, reviewing and auditing are done by **roles** through the relays. You never
write the feature code yourself when a role fits.

Use exactly the same process as the Claude Code skill, `~/orchestra-skills/skills/orchestrate/SKILL.md`
(read §0–§5 there), with these differences:

| Claude Code skill | Here |
|---|---|
| `task-router` subagent | classify it yourself with the rubric in `~/orchestra-skills/agents/task-router.md`, after a few quick looks (never a full read) |
| `lane-runner` subagent for feature/complex | you run §3 yourself for every level, following `~/orchestra-skills/agents/lane-runner.md` "For each task" |
| `completion-auditor` subagent (runs commands) | the **`final-audit` role**, read-only, can't run commands (see below) |

Everything else is identical:
- the tools: `~/orchestra-skills/scripts/orchestra route | resolve | budget | exhausted | metrics`
  and `brief-check.sh`;
- the policy (`references/policy.md`) and the card formats (`references/brief-template.md`);
- the budget: every call is recorded with `orchestra budget spend` first;
- delta retries, planner ≠ builder ≠ reviewer, and read-only reviews and planners;
- never end your turn while a relay runs.

## Final audit through the `final-audit` role (feature and complex)

A read-only auditor can't run commands, so **you run the checks and hand it the evidence**:

1. Run every **Verify** command from the plan and save the commands with their full output to
   `${TMPDIR:-/tmp}/orchestrate/<repo>/final-audit/verify.txt`. In the same folder, save
   `git log --oneline <base>..HEAD` plus `git diff <base>..HEAD` as `diff.patch`, and
   `git status --porcelain` as `status.txt`.
2. `orchestra resolve final-audit` → `orchestra budget spend <run> final-audit <model>`.
3. Brief: `~/orchestra-skills/agents/completion-auditor.md` below its front-matter, plus "Plan:
   <path>. Repo: <path>. Base commit: <sha>. You cannot run commands: the Verify output is in
   verify.txt, the diff and commits in diff.patch, the working-tree status in status.txt (all in
   <folder>). Read and judge them, and inspect tracked files for the rest. Return DONE or GAPS."
4. `DONE` → report. `GAPS` → build the gaps (§3), then re-verify deterministically (Verify plus the
   `review` role). Call the auditor again only if `final_audit.max_calls` allows.

**Never tell the user a feature/complex task is finished without the final audit's `DONE`.**
