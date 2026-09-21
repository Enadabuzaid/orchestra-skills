---
name: orchestrate-portable
description: >-
  The orchestrate workflow for apps without Claude Code subagents (Codex app/CLI, Cursor, …). A cheap
  route step sends simple and medium work straight to job lanes. The plan comes from the `planner`
  lane (Fable by default), hard plans are challenged by a different model family
  (`architecture-review`), each task goes to a job lane (backend, frontend, tests, refactor, debug,
  docs) as a tight task card with code/ui/security reviews, and the read-only `final-audit` lane
  decides DONE. Use when the user says "orchestrate" in Codex or another non-Claude-Code app. In
  Claude Code, use the `orchestrate` skill instead.
license: MIT
metadata:
  author: Enad Abuzaid
  homepage: https://github.com/Enadabuzaid/orchestra-skills
  version: 0.5.0
  requires: amElnagdy/delegate-skills (claude-delegate, codex-delegate, agy-delegate, delegate-setup), a clone of orchestra-skills at ~/orchestra-skills
---

# Orchestrate (portable)

You are the **orchestrator**. You route, dispatch, check and commit. Planning, building, reviewing
and the final audit are done by **job lanes** through the delegate-skills relays. You never skip a
gate, and never commit before the task's gate passes.

## Two principles

1. **Context isolation.** Every planner, implementer, reviewer and auditor receives one card or
   brief with only the facts it needs. Never the conversation, the plan discussion, old attempts,
   other tasks, or whole files. Task cards follow `REF/brief-template.md` and must pass
   `~/orchestra-skills/scripts/brief-check.sh <card>` before they're sent.
2. **Lanes are jobs, not vendors.** Resolve every job with `~/orchestra-skills/scripts/lanes.sh
   resolve <job>` (prints the lane, tool and model; accepts older names). Never name a vendor in a
   plan or card. The jobs and their rules are in `REF/lanes.md`.

## Paths

- `RELAY(<tool>)` = `~/.claude/skills/<tool>-delegate/scripts/relay.mjs` (or the same path under
  `~/.codex/skills/` / `~/.agents/skills/`, whichever exists).
- `REF` = `~/orchestra-skills/skills/orchestrate/references` (plan template, card template, lanes).
- `AGENTS` = `~/orchestra-skills/agents` (the router, reviewer and auditor instructions).
- Run dirs: `${TMPDIR:-/tmp}/orchestrate/<repo-name>/<step>/`, **never inside the repo**.
- When a lane's tool is `claude`, prefix the command with `env -u ANTHROPIC_API_KEY` (subscription billing).
- **Never end your turn while a relay is running.** Block until `result.json` exists:
  `until [ -f <dir>/result.json ]; do sleep 15; done`.
- **Fallback chain for any job:** `<job>` → `<job>-fallback` → `fallback`. For planners: `planner` →
  `planner-fallback` → `planner-alt`. Always report which lane ran.

## Stage 0: Route (cheap)

Classify the request with the rubric in `AGENTS/task-router.md` (simple / medium / complex /
very-complex; when in doubt, pick the higher one). Take a few quick looks at the code, not a full
read. The user can override it.

- **simple**: no plan and no gates. One task card to the router's job (default `small`), run the
  area's tests, one commit, report. Done.
- **medium**: Stage 1 (`planner`) → Stages 3–6 → Stage 7. No architecture review.
- **complex**: Stage 1 (`planner`) → Stage 2 → Stages 3–6 → Stage 7.
- **very-complex**: Stage 1 (`planner-hard`, else `planner`) → Stage 2 → Stages 3–6 → Stage 7.

## Stage 1: Plan (the planner lane)

One planner produces the architecture, read-only; you save its output.

1. `git status` must be clean (otherwise ask the user to commit or stash). Record the base commit.
2. Planner brief: the request, "Repo: <abs path>. Base commit: <sha>. Explore the code read-only,
   then reply with ONLY the complete plan in markdown, following this template:", and the text of
   `REF/plan-template.md`. The plan needs Tasks (a **job** per task from `REF/lanes.md`, files,
   acceptance, task gate, `Sensitive`, status), Contracts, a Definition of Done, Verify (the repo's
   real commands plus one runtime check), and Out of scope.
3. `node RELAY(<tool>) --lane <planner lane> --read-only --brief <brief> --cd <repo> --out-dir <run>/plan/<lane> --timeout 45m`.
   On quota, permission or availability failures, go down the planner chain. If no planner lane is
   configured, plan in this session and say so.
4. Save `finalMessage` to `docs/plans/<YYYY-MM-DD>-<feature>.md` with `Planner: <lane> (<tool>
   <model>)` under the title. Check the required sections, run Verify once to record the baseline,
   and commit the plan.

## Stage 2: Architecture review by a different model family (complex and very-complex)

Use the `architecture-review` job, unless its tool is the same family as the planner that actually
ran; then use `architecture-review-alt`. If neither is a different family, tell the user and use the
one that differs most (a different model at least).

1. Brief to `<run>/architecture-review/round-N/brief.md`: the text of `AGENTS/plan-reviewer.md`
   below its front-matter, plus "Plan file: <abs path>. Repo: <abs path>. Review the plan against the
   real code and reply APPROVE or CHANGES REQUIRED in the exact format above."
2. `node RELAY(<tool>) --lane <review lane> --read-only --brief <brief> --cd <repo> --out-dir <run>/architecture-review/round-N --timeout 30m`
3. `APPROVE` → mark the plan approved and commit it. `CHANGES REQUIRED` → send the planner a delta
   brief with the numbered fixes (`--session <id>` from its result), save the revised plan, and
   review again. After 3 rounds, show the user what is still disputed.

**No implementation before the plan is approved (complex+) or saved (medium).**

## Stages 3–6: Build each task

For each task, in plan order; tasks with disjoint files may run in parallel (`relayA & relayB & wait`):

1. **Task card** in the exact `REF/brief-template.md` format (TASK, Goal, Files, Contract, Rules,
   Acceptance, Do not), with only this task's facts. `brief-check.sh` must pass.
2. **Dispatch** to the task's job: `lanes.sh resolve <job>` →
   `node RELAY(<tool>) --lane <lane> --brief <card> --cd <repo> --out-dir <run>/<task>/run --timeout 45m`.
3. **Result:** a quota, permission or availability failure → the job's fallback chain. Never add
   `--dangerously-skip-permissions` or `--allow-all-tools`.
4. **Gate:** run the task gate. It fails → one delta card to the implementer. It still fails → a
   short card with the failing command and output to the `debug` job (if configured), then the
   fallback chain.
5. **Reviews.** Save `git diff -- <files>` and `git status --porcelain` to
   `<run>/<task>/review/diff.patch`, then send a read-only review card ("Review the diff in <file>
   against TASK <ID>: goal, rules, acceptance, allowed files. Reply PASS or numbered findings with
   file:line.") to each review job that applies and is configured: `code-review` (every task),
   `ui-review` (frontend tasks), `security-review` (tasks marked `Sensitive: yes`, or touching auth,
   permissions, payments, uploads, raw SQL, crypto or secrets). Reviews, and any fallback standing in
   for a review, always run with `--read-only`. Real findings → a delta card to the
   implementer (max 2 rounds). With no review job configured, review the diff yourself.
6. **Land:** run the plan's test command, then commit only this task's files and set Status to done
   in the plan, in the same commit. Plain conventional message, no Co-Authored-By trailer.

## Stage 7: Final audit (read-only), looped

A read-only auditor can't run commands, so **you run the checks and hand over the evidence**:

1. Run every **Verify** command, and save the commands with their full output to
   `<run>/final-audit/round-N/verify.txt`. Also save `git log --oneline <base>..HEAD` plus
   `git diff <base>..HEAD` to `diff.patch`, and `git status --porcelain` to `status.txt`, in the
   same folder.
2. Brief: the text of `AGENTS/completion-auditor.md` below its front-matter, plus "Plan: <abs path>.
   Repo: <abs path>. Base commit: <base>. You cannot run commands: the Verify output is in
   <verify.txt>, the feature diff and commits are in <diff.patch>, and the working-tree status is in
   <status.txt>. Read and judge all three, and inspect tracked files directly for everything else.
   Return DONE or GAPS in the exact format."
3. `node RELAY(<tool>) --lane <final-audit lane> --read-only --brief <brief> --cd <repo> --out-dir <run>/final-audit/round-N --timeout 30m`
4. `DONE` → Stage 8. `GAPS` → add `G1`, `G2`, … to the plan's task table (with the suggested job) and
   build them as in Stages 3–6, then audit again. After 3 rounds, stop and show the user the gaps.

**Never tell the user the feature is finished without the final audit's `DONE`.**

## Stage 8: Report

The route taken; which lanes and tools actually ran (including fallbacks); tasks → job/tool → commit;
the reviews' findings; each Verify command and its result; the manual checks left for the user; and
`~/orchestra-skills/scripts/token-report.sh <repo-name>`. Nothing is pushed.
