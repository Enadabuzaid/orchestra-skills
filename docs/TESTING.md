# Testing: step by step

Follow these steps in order. Each step says **what to run**, **what you should see**, **what it
proves**, and **what to do if it fails**. Steps 1–3 are automatic. Steps 4–6 are you watching it
work on a real feature.

| Step | What | Time | Uses quota? |
|---|---|---|---|
| 0 | Self-test: the scripts and the policy engine, with fake tools | 30 s | no |
| 1 | Doctor: everything installed and wired, which model each role uses now | seconds | no |
| 2 | Role smoke test: the model each role picks really codes | 1–2 min | a little |
| 3 | Automated end-to-end: the whole workflow, checked by a script | 10–25 min | yes (Fable + Opus + builders) |
| 4 | Watch it yourself on the demo app | 10–20 min | yes |
| 5 | Check the token savings | 1 min | no |
| 6 | First real feature in your own project | – | yes |

---

## Step 0. Self-test (also what CI runs)

```bash
~/orchestra-skills/scripts/self-test.sh
```

**You should see:** `All 10 zero-quota checks passed.`

**It proves:** every script parses on bash 3.2 (macOS) and bash 5; the installer backs up conflicts
and is idempotent and links `~/orchestra-skills` from any clone location; the doctor accepts a valid
setup and rejects a broken one; the smoke test rejects out-of-scope writes; task/delta/review cards
are validated; and the policy engine, with fake CLIs, resolves roles by availability, quota and
relay flags, keeps builder ≠ reviewer, refuses the 4th expensive call, validates policies
(`orchestra check`), and never caches a failed discovery.

## Step 1. Doctor

```bash
~/orchestra-skills/scripts/doctor.sh                 # the machine
~/orchestra-skills/scripts/doctor.sh ~/Code/my-app   # plus one project
```

**You should see:** a ✓ on every line, the role table with the model each role **uses now**, and
`N checks passed, 0 failed.` With a project path: git repository, clean tree, the detected test
command, and whether Antigravity may write there.

**It proves:** the `orchestrate` skill, the five agents (`task-router`, `lane-runner`,
`plan-reviewer`, `diff-reviewer`, `completion-auditor`), the CLAUDE.md rules, the relays, the policy
(validated by `orchestra check`) and the logins are all in place, and the project is ready.

**If it fails:** each ✗ line says the fix. A role with `NONE AVAILABLE` is followed by the reason for
every model in its chain and the `orchestra set` command to change it.

## Step 2. Role smoke test

```bash
~/orchestra-skills/scripts/smoke-test.sh role:backend role:frontend role:review role:docs   # roles, through the policy
~/orchestra-skills/scripts/smoke-test.sh backend ui                                          # older: lanes from the lane config
```

**You should see:** one row per role, with `PASS  multiply added, tests green, scope clean, not
committed` for building roles and `PASS  answered, no changes` for read-only roles.

**It proves:** the model each role resolves to right now really receives a card, writes working code,
**never commits**, and read-only roles never change files. The script checks the files and tests
itself; it doesn't trust what the CLI says.

**If it fails:** the row gives the reason, and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) has the fix.
A quota failure means that provider is out of quota; your setup is fine. Mark it so nothing tries it
again until it resets: `orchestra exhausted <tool> --until HH:MM` (or `--for 240h` for a monthly quota).

## Step 3. Automated end-to-end test

```bash
~/orchestra-skills/scripts/e2e-test.sh          # renderer task on Antigravity
~/orchestra-skills/scripts/e2e-test.sh --no-ui  # if you don't use Antigravity
```

A fresh, unattended Claude Code session builds a 3-task feature on the demo app with `orchestrate`.
It has to route, get the Fable plan, build through the lane-runner with the models the policy picks,
review each task with a different model, and pass the Opus completion loop. Then **the script
checks the result itself**:

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
~/orchestra-skills/scripts/token-report.sh
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

### v0.5.1 automated end-to-end (2026-09-21, after the fixes below)

`scripts/e2e-test.sh` with `E2E_MODEL=sonnet` (the session only coordinates). Codex came back from
its quota reset during the run; Copilot was out for the month; Kimi and DeepSeek not logged in.

| Check | Result |
|---|---|
| 17 script checks | **17 ✓** after fixing the script's own last check (see below); the run itself: `E2E-RESULT: DONE`, 22/22 tests, 4 commits, clean tree |
| Route | `feature`; 2 of 3 expensive calls (Fable plan, Opus audit) |
| Builders | T1 backend → **Codex**; T2 frontend → Antigravity (headless command denied) → **Codex**; T3 docs → **Luna** |
| Reviews | T1, T2: **Luna** (review + ui-review); T3: Haiku (Luna built it) |
| Who paid | **6 of 9 relay runs on ChatGPT.** Claude lanes: $0.66 (the Fable plan $0.52 + two Haiku reviews $0.14). No Claude token spent on code |
| Time | 70 min, of which ~16 min were Claude API retries before the planner's first token (`api_retry`, not quota: the 5-hour window was at 34%) |
| Cost | Claude session $1.25 (Sonnet $0.84, Opus $0.34, Haiku $0.07) + lanes $0.66 = **$1.91**, vs **$4.95** for the v0.5 run of the same feature |

What it found:

| Finding | Fix |
|---|---|
| The script's last check ("some coding ran on a non-Claude quota") failed although 6 runs were on Codex: `cat … \| grep -q` under `pipefail` fails as soon as grep matches (cat gets SIGPIPE). It could only show once non-Claude runs existed | grep over the files directly (v0.5.1 follow-up) |
| The lane-runner sent one review card that had failed `brief-check.sh` | lane-runner rule: a card that fails the check is never sent |
| The T3 reviewer was Haiku while `orchestra resolve review --not-model luna` gives the free OpenCode model | lane-runner rule: use the model `resolve` printed, `--not-family` only for security-review |
| Antigravity was denied a headless command again, even with `agy-allow.sh --tests node` | falls back as designed; see TROUBLESHOOTING for the allow rule |

### v0.5 automated end-to-end (2026-09-21, the run that shaped v0.5.1)

`scripts/e2e-test.sh`, Claude orchestrating on Opus, with **Codex out of quota** for the whole run
and Copilot's monthly premium quota used up.

| Check | Result |
|---|---|
| 17 script checks | **16 ✓**, `E2E-RESULT: DONE`. The one ✗: "some coding ran on a non-Claude quota", because every non-Claude builder was unavailable |
| Route | `feature`; no second opinion (no architecture/security/payments/migrations areas); **2 of 3 expensive calls** used (Fable plan, Opus audit) |
| Fallbacks | backend: Codex (quota) → Sonnet. frontend: Antigravity (headless command permission denied) → Sonnet. Both recorded in `orchestra metrics` |
| Time | 171 min, of which about 150 were a network outage (`ENOTFOUND` on a review) and two interrupted lane-runner turns, not model work |
| Cost | Claude orchestrator + subagents $3.69 (Opus $2.03, Sonnet $1.61, Haiku $0.05); relay runs $1.26 |

What it found, and what changed because of it:

| Finding | Fix (v0.5.1) |
|---|---|
| The policy engine reported **every CLI as "not installed"** for 15 minutes: a discovery probe failed and its empty result was cached | A failed or empty discovery is never cached; the last good result, then a PATH check, is used. `doctor.sh` always re-probes and prints the reason per model |
| **Haiku as the `docs` builder** used 478k input tokens in 21 turns, then 174k more on the retry, for one README | Haiku is out of every builder chain; it only reviews and routes |
| Every fallback landed on Sonnet: the default policy had no other affordable tier | GPT-5.6 Luna (ChatGPT) and OpenCode's free tier (`opencode/big-pickle`, smoke-tested) come before Sonnet in every chain; Copilot reviews read-only; `orchestra check` enforces the read-only rules |
| `budget start` was run without `--dir`, so `metrics` found no relay runs | `metrics` now finds the run folder from the run id |

### Tiny route through the skill (2026-09-21, v0.5.1 policy, Codex out of quota)

A headless Sonnet session (`claude -p`, `/model sonnet`) on a copy of the demo app: *"the error
message 'title is required' should become 'a title is required' (update the test too)"*.

| | |
|---|---|
| Route | `tiny` (task-router: one task, two files, no risky areas) → no plan, no reviewer, no audit |
| Card | 112 tokens, passed `brief-check.sh` |
| Builder | `small` → **`opencode/big-pickle` (free tier)**: Codex/Luna out of quota, Kimi not installed, DeepSeek no key |
| Relay | `completed` in ~40 s; touched only `todos.js` and `todos.test.js`; 3/3 tests |
| Landed | one commit, clean tree, no trailer; the session re-ran the tests and read the diff itself before committing |
| Metrics | expensive calls 0/3, fallbacks 0, retries 0 |
| Cost / time | Claude session **$0.25, 11 turns**; typing **$0**; **83 s** prompt to finished report |

Same $0.25 as the v0.5 tiny run, but the typing moved from Sonnet to a free model.

### Role smoke test (2026-09-21, v0.5.1 policy, Codex and Copilot out of quota)

| Role | Resolved to | Result |
|---|---|---|
| planner-light | claude sonnet (read-only) | PASS, answered, no changes (8 s) |
| frontend | agy gemini-3.8-flash-high | PASS (25 s) |
| docs | agy gemini-3.8-flash-high | PASS (36 s) |
| backend | claude sonnet | PASS (19 s) |
| review | copilot (read-only) | FAIL: 402 `quota_exceeded` (monthly premium quota). Reported as quota, setup fine; marked `orchestra exhausted copilot --for 240h` |
| opencode `opencode/big-pickle` (free) | opencode | PASS (25 s) |
| opencode `opencode/nemotron-3-ultra-free` (free) | opencode | PASS (48 s) |

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
