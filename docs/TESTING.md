# Testing

There are three levels of testing. Run them in order: each one assumes the one before it passes.

| Level | Command / prompt | Time | Checks |
|---|---|---|---|
| 1. Doctor | `scripts/doctor.sh` | seconds | Everything is installed, linked and configured, and the CLIs are logged in |
| 2. Lane smoke test | `scripts/smoke-test.sh` | ~1–2 min | Every lane really runs its CLI, writes code (or answers read-only), and never commits |
| 3. End-to-end | the prompt below, in Claude Code | ~10 min | The full workflow: plan → Opus gate → lanes → Sonnet review → commit → Opus completion loop |

## 1. Doctor

```bash
~/orchestra-skills/scripts/doctor.sh
```

It exits `0` when everything is in place and lists anything missing, with the fix. It never changes
anything.

## 2. Lane smoke test

```bash
~/orchestra-skills/scripts/smoke-test.sh              # every lane in your config
~/orchestra-skills/scripts/smoke-test.sh ui backend   # only some lanes
SMOKE_TIMEOUT=20m ~/orchestra-skills/scripts/smoke-test.sh complex   # slower models
```

For each lane it:

1. creates a throwaway git repo with `math.js` (`add()`) and a `node:test` file;
2. sends that lane a real brief through its relay (`--lane <name>`):
   - **write lanes:** "add `multiply()` and a test, run `node --test`, do not commit";
   - **read-only lanes:** "list the exported functions, don't edit";
3. checks the outcome itself instead of trusting the CLI's report: `multiply` exists, `node --test`
   passes, there is still exactly one commit, and read-only lanes changed nothing.

Lanes run in parallel (Copilot runs last because of its 10s start-up check). The exit code is the
number of failed lanes. Logs stay in the printed work dir.

A failure caused by an exhausted quota is reported as such; your setup is fine in that case.

## 3. End-to-end test with the demo app

`examples/demo-app` is a tiny todo store (plain Node, no dependencies). Copy it somewhere, make it a
git repo, and let orchestrate build a 3-task feature:

```bash
cp -R ~/orchestra-skills/examples/demo-app ~/orchestra-demo && cd ~/orchestra-demo
git init -q && git add -A && git commit -qm "chore: demo baseline"
~/orchestra-skills/scripts/agy-allow.sh . --tests "node --test"   # lets the ui lane write here
claude
```

Then, in Claude Code (on Opus):

> Use orchestrate to add due dates to this todo app:
> T1 (backend): `add(title, { due })` with YYYY-MM-DD validation, and `overdue(today)`.
> T2 (ui): a pure `renderTodos(todos, today)` HTML renderer that escapes titles, plus a static index.html.
> T3 (small): a README documenting the API.
> T1 and T2 can run in parallel.

What you should see:

1. A plan in `docs/plans/…`.
2. `plan-reviewer` (Opus) replying `CHANGES REQUIRED` or `APPROVE`. A good reviewer usually finds
   something in a first draft, and Claude revises the plan until it gets `APPROVE`.
3. T1 → Codex and T2 → Antigravity running at the same time, then T3 → Claude Sonnet.
4. A `diff-reviewer` `PASS`/`FAIL` per task.
5. One commit per task, made by Claude.
6. The Opus completion loop: `DONE`, or `GAPS` turned into fix tasks until `DONE`.

Check afterwards: `git log --oneline` shows the plan and the task commits, and `node --test` is green.

### Reference run (2026-09-21)

This is what happened when we ran exactly this test while building the repo:

| Stage | Who | Result |
|---|---|---|
| 1. Plan | Claude Opus 5 | 3 tasks: T1 `backend`, T2 `ui` (parallel), T3 `small` |
| 2. Plan gate, round 1 | `plan-reviewer` (Opus) | **CHANGES REQUIRED**, 5 real issues: (1) parallel tasks would run each other's half-written tests; (2) `due: null` not specified; (3) `new Date('2026-02-30')` silently rolls over to March, so the check needs a UTC round-trip plus leap-year tests; (4) the renderer had almost no acceptance tests; (5) module format not stated, and index.html loading render.js would break in the browser |
| 2. Plan gate, round 2 | `plan-reviewer` (Opus) | **APPROVE** |
| 4. T1 | Codex (`backend`) | completed; 25 tests; touched only its 2 files; no commit |
| 4. T2 (in parallel) | Antigravity, Gemini 3.8 Flash (`ui`) | completed; 15 tests; 3 new files; no commit |
| 5. Review T1, T2 | `diff-reviewer` (Sonnet) ×2 | **PASS**, **PASS**, no risky hunks |
| 6. Land | orchestrator | full `node --test`: 40/40; 2 commits |
| 4–6. T3 | Claude Sonnet (`small`) | README written; 40/40; committed |
| 7. Final audit | Opus | **1 real bug**: the README's `overdue()` example showed a todo that was never added (the implementer's self-check missed it). Fixed through the `small` lane, verified with `node -e`, committed |

Final history of the demo repo:

```
e4bc791 docs: fix README overdue() example (final audit finding)
03c4df5 docs: README for todo API and renderer (T3, claude sonnet)
87db618 feat: HTML todo renderer and static page (T2, antigravity)
29eb139 feat: due dates and overdue() query (T1, codex)
55ac3e8 docs: revise plan after review round 1
753cd8b docs: plan for due dates
edb4f8e chore: demo app baseline
```

**Takeaways.** Each gate caught something the stage before it missed: the Opus plan gate caught
design bugs before any code existed, and the Opus final audit caught a cross-file mistake that
passed both the implementer's own check and the tests. Opus did three short reads (about 10k–46k
tokens each); all the code was written on Codex, Antigravity and Sonnet.

## Lane smoke test results (2026-09-21)

| Lane | CLI | Result |
|---|---|---|
| plan-check | codex (gpt-6-astra, read-only) | PASS |
| complex | codex (gpt-6-astra) | PASS |
| backend | codex | PASS |
| ui | agy (gemini-3.8-flash-high) | PASS after `scripts/agy-allow.sh` (before that: write permission auto-denied) |
| small | claude (sonnet) | PASS |
| fallback | claude (sonnet, high) | PASS |
| copilot-review | copilot (read-only) | FAIL: monthly premium quota used up (402), so it couldn't be tested this month. Its headless writes also need `--allow-all-tools`, which is why this lane is read-only |

## Completion-loop test (2026-09-21)

This checks that Opus refuses to call a feature finished when an implementer only *claims* it is
done. On a branch of the demo, all three tasks were marked `done` in the plan, but the README (T3)
was never delivered. The plan had a Definition of Done and Verify commands (from
`references/plan-template.md`).

| Round | `completion-auditor` (Opus) | What happened |
|---|---|---|
| 1 | **GAPS** | Checked 11 plan items with `file:line` evidence and ran `node --test` (40/40) plus the runtime check. Found `README.md missing … plan says T3 "done"`, and wrote the fix task with lane `small` |
| – | – | Gap G1 → Claude Sonnet (`small`) → gate 40/40 → committed, with the plan's task table and gap log updated |
| 2 | **DONE** | All items checked. It also ran all 12 README examples, and their output matched the documented results exactly. It listed the browser check as `manual` for the human |

Opus usage: ~46k tokens (round 1) + ~53k tokens (round 2). All the fixing was done on Sonnet.

Measured per-run usage (`scripts/token-report.sh`) for the end-to-end run:

```
RUN           LANE      TOOL    MODEL                 STATUS     IN TOKENS   OUT      USD     PAID BY
run-T1        backend   codex   default               completed  113,633     1,905    –       ChatGPT
run-T2        ui        agy     gemini-3.8-flash-high completed  –           –        –       Google
run-T3        small     claude  sonnet                completed  82,064      2,469    $0.077  Claude
run-T3fix     small     claude  sonnet                completed  183,085     3,102    $0.093  Claude
```
