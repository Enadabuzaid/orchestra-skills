# Testing: step by step

Follow these steps in order. Each step says **what to run**, **what you should see**, **what it
proves**, and **what to do if it fails**. Steps 1–3 are automatic. Steps 4–6 are you watching it
work on a real feature.

| Step | What | Time | Uses quota? |
|---|---|---|---|
| 1 | Doctor: everything installed and wired | seconds | no |
| 2 | Lane smoke test: every CLI really codes | 1–2 min | a little |
| 3 | Automated end-to-end: the whole workflow, checked by a script | 10–25 min | yes (Opus + lanes) |
| 4 | Watch it yourself on the demo app | 10–20 min | yes |
| 5 | Check the token savings | 1 min | no |
| 6 | First real feature in your own project | – | yes |

---

## Step 1. Doctor

```bash
~/orchestra-skills/scripts/doctor.sh
```

**You should see:** a ✓ on every line, the lane table, and `N checks passed, 0 failed.`

**It proves:** the `orchestrate` skill, all three agents (`plan-reviewer`, `diff-reviewer`,
`completion-auditor`), the CLAUDE.md rules, the delegate-skills and your lane config are all in
place, and which CLIs are logged in.

**If it fails:** each ✗ line says the fix (usually `./install.sh`, or a login).

## Step 2. Lane smoke test

```bash
~/orchestra-skills/scripts/smoke-test.sh              # all lanes
~/orchestra-skills/scripts/smoke-test.sh backend ui   # just some
```

**You should see:** one row per lane, with `PASS  multiply added, tests green, not committed` for
write lanes and `PASS  answered, no changes` for read-only lanes.

**It proves:** each CLI (Codex, GPT-6 Astra, Antigravity, Sonnet, Copilot) really receives a brief,
writes working code, **never commits**, and read-only lanes never change files. The script checks the
files and tests itself; it doesn't trust what the CLI says.

**If it fails:** the row gives the reason, and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) has the fix.
A quota failure means that provider is out of quota; your setup is fine.

## Step 3. Automated end-to-end test

```bash
~/orchestra-skills/scripts/e2e-test.sh          # renderer task on Antigravity
~/orchestra-skills/scripts/e2e-test.sh --no-ui  # if you don't use Antigravity
```

A fresh, unattended Claude Code session (Opus) builds a 3-task feature on the demo app with
`orchestrate`. It has to go through the Opus plan gate, the lanes, the Sonnet reviews and the Opus
completion loop. Then **the script checks the result itself**:

| Check | Proves |
|---|---|
| plan in `docs/plans/` with Definition of Done + Verify | Stage 1 followed the plan template |
| impossible date `2026-02-30` rejected; `overdue()` order and exclusions right | T1 really works (tested by the script with its own cases) |
| renderer escapes `<b>` and marks overdue | T2 really works |
| README exists; full test suite passes with more tests than the baseline | T3 delivered; tests were added |
| clean tree; at least 4 commits; no Co-Authored-By | Claude landed every task and nothing was left behind |
| final line `E2E-RESULT: DONE` | the completion-auditor reached DONE |
| relay runs found; some run on Codex/Antigravity | the coding really was delegated, off your Claude quota |

It also prints the commits, the Claude cost (by model), and the token report for every delegated run.

**You should see:** `N checks passed, 0 failed.`

**If it fails:** the work dir is printed. `claude.json` has Claude's full final answer, and the demo
repo inside it shows exactly what was built.

## Step 4. Watch it yourself

This is the same test, done by hand so you can watch every stage happen:

```bash
cp -R ~/orchestra-skills/examples/demo-app ~/orchestra-demo && cd ~/orchestra-demo
git init -q && git add -A && git commit -qm "chore: demo baseline"
~/orchestra-skills/scripts/agy-allow.sh . --tests "node --test"
claude
```

In Claude Code, run `/model` → **Opus**, then paste:

> Use orchestrate to add due dates to this todo app.
> T1 (backend): `add(title, { due })` with YYYY-MM-DD validation, and `overdue(today)`.
> T2 (ui): a pure `renderTodos(todos, today)` HTML renderer that escapes titles, plus a static index.html.
> T3 (small): a README documenting the API. T1 and T2 can run in parallel.

Tick these off as you watch:

- [ ] A plan appears in `docs/plans/` with **Tasks**, **Definition of Done** and **Verify**
- [ ] `plan-reviewer` replies `APPROVE` or `CHANGES REQUIRED`, and Claude revises the plan until `APPROVE`
- [ ] No code is written before `APPROVE`
- [ ] T1 goes to Codex and T2 to Antigravity, at the same time (`relay: completed · codex` / `· agy`)
- [ ] A `diff-reviewer` `PASS`/`FAIL` for each task
- [ ] Claude re-runs `node --test` and commits each task (`git log --oneline` in another terminal)
- [ ] T3 goes to Claude Sonnet (`small`)
- [ ] `completion-auditor` replies with a checklist, verify results and `DONE` (or `GAPS`, followed by fixes and another round)
- [ ] The final report lists the tasks, commits, verify results and a manual check for you

Then do the manual check yourself: open `index.html`. The overdue item should be red and the done
item struck through.

## Step 5. Check the token savings

```bash
~/orchestra-skills/scripts/token-report.sh "$TMPDIR"/delegate-relay/*
```

Each delegated run shows its tokens and **who paid**: ChatGPT (Codex), Google (Antigravity),
GitHub (Copilot) or Claude (Sonnet lanes). In Claude Code, `/cost` shows what the orchestrator
itself spent. Compare that with a session where Opus writes everything itself.

## Step 6. First real feature

In your own project:

1. Allow Antigravity there once: `~/orchestra-skills/scripts/agy-allow.sh <project> --tests "<your test command>"`.
2. `/model` → Opus, then *"Use orchestrate to build …"*.
3. Check that the plan's **Verify** section uses your project's real commands (tests, static
   analysis, build) before you let it continue.
4. At the end, check the final report, run your tests once yourself, and push.

---

## Recorded results

### Run 1: guided end-to-end (2026-09-21)

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

### Lane smoke test (2026-09-21)

| Lane | CLI | Result |
|---|---|---|
| plan-check | codex (gpt-6-astra, read-only) | PASS |
| complex | codex (gpt-6-astra) | PASS |
| backend | codex | PASS |
| ui | agy (gemini-3.8-flash-high) | PASS after `scripts/agy-allow.sh` (before that: write permission auto-denied) |
| small | claude (sonnet) | PASS |
| fallback | claude (sonnet, high) | PASS |
| copilot-review | copilot (read-only) | FAIL: monthly premium quota used up (402), so it couldn't be tested this month. Its headless writes also need `--allow-all-tools`, which is why this lane is read-only |

### Completion-loop test (2026-09-21)

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

### Automated end-to-end runs (`scripts/e2e-test.sh`, 2026-09-21)

These are the three unattended runs made while building v0.2.0. Each failure led to a fix.

| Run | Result | What it showed | Fix |
|---|---|---|---|
| 1 | 7/17 | Claude started the relays in the background and ended its reply, which ends a headless session and killed the relays (`aborted … SIGTERM`). Only the plan was committed | The skill now blocks until every `result.json` exists |
| 2 | **15/16 feature checks ✓, `E2E-RESULT: DONE`** | Plan approved in 1 round. T1 on Codex. T2: Antigravity was denied a shell command, and Claude **refused to widen permissions unattended** and rerouted T2 to `fallback` (Sonnet). 3 × PASS reviews, completion-auditor `DONE`. The last check failed only because the script couldn't find the run logs | Logs go to a fixed location outside the repo; the script's run discovery was fixed; `agy-allow.sh` now allows `node` |
| 3 | stopped | `API Error: 400 You have reached your specified API usage limits` from the `ANTHROPIC_API_KEY` in the environment | Not a workflow bug. The test now reports API errors clearly. Re-run after the limit resets, or with subscription auth |

**Cost of run 2**, which is what led to the `lane-runner`:

| Who | Cost | Notes |
|---|---|---|
| Codex (T1) | $0 Claude | 121k tokens on the ChatGPT quota |
| Sonnet lanes (T2 fallback, T3) | $0.57 | |
| Opus orchestrator + gates | **$3.97** | 54 turns: most of it was coordination (briefs, waiting, commits), not thinking |

The orchestrator doing routine coordination on Opus was ~92% of the Claude cost. Since v0.2.0,
Stages 3–6 run on the Sonnet `lane-runner`, and Opus only plans and runs the two gates. Re-run
`scripts/e2e-test.sh` to measure the difference on your own account.
