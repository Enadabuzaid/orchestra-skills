# The complete guide

This guide explains how orchestra-skills works, how to install it, and how to use it day to day.
Read it top to bottom once; afterwards the [cheat sheet](#cheat-sheet) at the end is enough.

- [1. The idea](#1-the-idea)
- [2. How the pieces fit](#2-how-the-pieces-fit)
- [3. Which model does what](#3-which-model-does-what)
- [4. Install, step by step](#4-install-step-by-step)
- [5. Check it works](#5-check-it-works)
- [6. Your first feature, step by step](#6-your-first-feature-step-by-step)
- [7. What happens at each stage](#7-what-happens-at-each-stage)
- [8. Lanes: choosing who does the work](#8-lanes-choosing-who-does-the-work)
- [9. Changing lanes and models](#9-changing-lanes-and-models)
- [10. Permissions and safety](#10-permissions-and-safety)
- [11. Saving tokens: what actually saves them](#11-saving-tokens-what-actually-saves-them)
- [12. Using it without orchestrate](#12-using-it-without-orchestrate)
- [Cheat sheet](#cheat-sheet)

---

## 1. The idea

Strong models (Claude Fable, Claude Opus, GPT-6 Astra) are great at **thinking**: understanding a
feature, finding the risks, and designing the plan. They are expensive.

Most of the tokens in a coding session are spent on **typing**: writing files, running tests,
fixing lint. Cheaper models (Codex default, Gemini Flash, Claude Sonnet) do that well when they get
a clear, small instruction.

orchestra-skills splits the work that way:

```
 You ──▶ Claude (Opus/Fable) ── plans ──▶ Opus plan-reviewer ── APPROVE ──▶ task briefs
                                                                         │
             ┌───────────────────────┬───────────────────────┬──────────┘
             ▼                       ▼                       ▼
        Codex (backend)       Antigravity (ui)       Claude Sonnet (small)
             │                       │                       │
             └──────── diffs ────────┴───────────┬───────────┘
                                                 ▼
                                 Sonnet diff-reviewer: PASS / FAIL
                                                 ▼
                           Claude re-runs tests and commits (only Claude commits)
                                                 ▼
                     Opus completion-auditor: every plan item + verify commands
                         DONE ──▶ report to you      GAPS ──▶ fix tasks ──▶ lanes ──▶ audit again
```

The main Claude session is the **orchestrator**. It never hands its long chat history to anyone.
Each implementer gets a short brief (about one page) and works in its own session, on its own quota.

## 2. How the pieces fit

There are two open-source projects working together:

| Project | What it gives you | Who maintains it |
|---|---|---|
| [delegate-skills](https://github.com/amElnagdy/delegate-skills) | One skill per coding CLI (`codex-delegate`, `agy-delegate`, `claude-delegate`, `copilot-delegate`, …). Each one sends a brief to that CLI, waits, and writes `result.json`. Plus `delegate-setup` for lanes. | amElnagdy |
| **orchestra-skills** (this repo) | The process on top: the `orchestrate` skill, the Opus `plan-reviewer`, the Sonnet `diff-reviewer`, the brief template, the lane map, and test scripts. | you |

We don't fork delegate-skills. We install it as it is and build on top of it, so you get its
updates for free.

Files installed on your machine:

| Path | What it is |
|---|---|
| `~/.claude/skills/orchestrate/` | The 8-stage workflow (symlink to this repo) |
| `~/.claude/agents/plan-reviewer.md` | Opus subagent that approves or rejects plans |
| `~/.claude/agents/diff-reviewer.md` | Sonnet subagent that reviews each task's diff |
| `~/.claude/agents/completion-auditor.md` | Opus subagent that decides when the feature is really finished |
| `~/.claude/CLAUDE.md` | A short block of rules between `orchestra-skills` markers |
| `~/.claude/skills/*-delegate/` | The implementer skills from delegate-skills |
| `~/.config/delegate-skills/config.json` | Your lanes: which CLI and model does which job |

Because the skill and agents are **symlinks**, `git pull` in this repo updates them at once.

## 3. Which model does what

| Job | Model | Why this one |
|---|---|---|
| Plan the feature | **Claude Fable 5.1** or **Opus 5** | Deepest reasoning; runs once per feature |
| Check the plan (mandatory) | **Claude Opus 5** (`plan-reviewer`) | Fresh eyes; verifies the plan against the real code |
| Second opinion on big plans (optional) | **GPT-6 Astra** (`plan-check` lane) | A different model family catches different mistakes |
| Large or tricky implementation | **GPT-6 Astra** (`complex` lane) | For cross-cutting refactors and hard logic |
| Normal backend work | **Codex default** (`backend` lane) | Cheap and strong at server code and tests |
| UI work | **Gemini 3.8 Flash** via Antigravity (`ui` lane) | Fast, large context, generous quota |
| Small fixes, docs, lint | **Claude Sonnet 5** (`small` lane) | Cheap and precise |
| When a lane fails or hits its quota | **Claude Sonnet 5, high effort** (`fallback` lane) | Reliable backup |
| Review each diff | **Claude Sonnet 5** (`diff-reviewer`) | Reads line by line so Opus doesn't have to |
| Decide when it's finished (loops until DONE) | **Claude Opus 5** (`completion-auditor`) | Checks every plan item and runs the verify commands |
| Extra opinion (optional) | **Copilot** (`copilot-review` lane, read-only) | When you have Copilot quota to spare |

## 4. Install, step by step

You need: macOS or Linux, Node 18+, git, and Claude Code. Then:

**Step 1. Install the CLIs you want to use and log in to each one once.**

| CLI | Install | Log in |
|---|---|---|
| Claude Code | already have it | already logged in |
| Codex | `npm i -g @openai/codex` | `codex login` |
| Antigravity | from Antigravity's CLI docs (`agy`) | run `agy` once interactively |
| Copilot (optional) | `gh extension install github/gh-copilot` or the standalone `copilot` CLI | `gh auth login` |

You don't need all of them. Missing CLIs just mean you move their lane to one you have (section 9).

**Step 2. Install the implementer skills.**

```bash
npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \
  --skill codex-delegate --skill agy-delegate --skill claude-delegate \
  --skill copilot-delegate --skill delegate-setup
```

**Step 3. Install orchestra-skills.**

```bash
git clone https://github.com/Enadabuzaid/orchestra-skills ~/orchestra-skills
~/orchestra-skills/install.sh
```

`install.sh` links the skill and the three agents into `~/.claude`, adds the rules block to
`~/.claude/CLAUDE.md`, and writes the default lanes if you don't have any yet. It is safe to run again.

**Step 4. Let Antigravity write in your project folders** (only if you use the `ui` lane).

Headless Antigravity can't ask you for permission, so it refuses to write unless a rule allows it.
Allow **only** your projects folder:

```bash
~/orchestra-skills/scripts/agy-allow.sh ~/Code                            # your projects folder
~/orchestra-skills/scripts/agy-allow.sh ~/Code/my-app --tests "npm test"  # optional: let it run tests
```

**Step 5. Restart Claude Code** so it picks up the new agents.

## 5. Check it works

```bash
~/orchestra-skills/scripts/doctor.sh       # checks everything is installed (changes nothing)
~/orchestra-skills/scripts/smoke-test.sh   # sends a tiny real task to every lane
```

`smoke-test.sh` creates a throwaway git repo per lane and asks each CLI to add a `multiply()`
function and a test. A lane passes only if the code was added, `node --test` is green, and the CLI
did **not** commit. Read-only lanes must answer and change nothing. Expected output:

```
LANE            TOOL     RESULT DETAIL
plan-check      codex    PASS   answered, no changes (18s)
complex         codex    PASS   multiply added, tests green, not committed (35s)
backend         codex    PASS   multiply added, tests green, not committed (36s)
ui              agy      PASS   multiply added, tests green, not committed (46s)
small           claude   PASS   multiply added, tests green, not committed (23s)
fallback        claude   PASS   multiply added, tests green, not committed (30s)
copilot-review  copilot  FAIL   copilot quota or rate limit reached; the setup is fine, retry after it resets
```

(That's a real run from 2026-09-21: every lane passed except Copilot, whose monthly premium quota was
used up. The test reports the quota as the cause, so you know the setup itself is fine.)

Test only some lanes: `scripts/smoke-test.sh backend ui`. See [TESTING.md](TESTING.md) for the full
end-to-end test and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if a lane fails.

## 6. Your first feature, step by step

1. **Open Claude Code in your project** and pick a thinking model:
   `/model` → **Opus** (or **Fable** for the hardest features).

2. **Ask for the feature through orchestrate:**

   > Use orchestrate to add CSV export to the reports page.

   Or just describe a multi-step feature. The CLAUDE.md rules tell Claude to use orchestrate for
   anything with more than about two tasks.

3. **Answer Claude's questions** about the feature. Then Claude writes a plan to
   `docs/plans/<date>-<feature>.md` listing each task, its files, its tests and its lane.

4. **Watch the plan gate.** Claude sends the plan to `plan-reviewer` (Opus). You'll see either
   `APPROVE` or `CHANGES REQUIRED` with a numbered list. Claude fixes the plan and asks again, up
   to 3 rounds. If they still disagree, Claude shows you the disagreement and you decide.

5. **Optional second opinion.** For big or risky features, say *"also get Astra's opinion"* and
   the plan goes to GPT-6 Astra (read-only) too.

6. **Implementation runs in the background.** Claude writes one brief per task and sends each to
   its lane. Tasks that touch different files run at the same time. You'll see lines such as
   `relay: completed · codex` as they finish.

7. **Each result is reviewed.** `diff-reviewer` (Sonnet) runs the tests and reads the diff, then
   returns `PASS` or `FAIL`. On `FAIL`, the same implementer gets a short follow-up brief. After two
   failures, the task moves to the `fallback` lane.

8. **Claude commits.** Claude runs the tests once more and commits each task with a clear message.
   Implementers never commit, and nothing is pushed.

9. **Completion loop (Opus decides when it's finished).** The `completion-auditor` (Opus) goes
   through every task and every **Definition of Done** item in the plan and checks each one against
   the real code, with `file:line` evidence. It runs every **Verify** command (tests, static
   analysis, build, and a runtime check that actually exercises the feature), checks that tasks from
   different implementers fit together, and looks for leftovers such as debug code, TODOs or
   uncommitted files.
   - **DONE**: the feature is finished.
   - **GAPS**: each gap becomes a new task (`G1`, `G2`, …) that goes through a lane, the reviewer
     and a commit, then the auditor runs again. Up to 3 rounds; after that Claude shows you what's
     left instead of pretending it's finished.

   Claude never tells you a feature is finished without the auditor's `DONE`.

10. **Final report.** Claude lists what was built (task → commit → implementer), each verify
    command and its result, what the gates caught along the way, and anything left for you to
    check by hand (for example "open the page and click X").

11. **You review and push.** Look at `git log` and push when you're happy.

## 7. What happens at each stage

| Stage | Who | Input | Output | Big-model tokens? |
|---|---|---|---|---|
| 1 Plan | Fable/Opus (your session) | your request + code | `docs/plans/…md` | yes, once |
| 2 Plan gate | Opus `plan-reviewer` | plan path | `APPROVE` / fixes | yes, short |
| 2b Second opinion | GPT-6 Astra (`plan-check`) | plan | `APPROVE` / fixes | on ChatGPT quota |
| 3 Briefs | orchestrator | the plan | one ~1-page brief per task | small |
| 4 Implement | lanes | brief only | code changes + `result.json` | **none** (other quotas) |
| 5 Review | Sonnet `diff-reviewer` | brief + diff | `PASS`/`FAIL` + findings | Sonnet, not Opus |
| 6 Land | orchestrator | reviewer summary | tests re-run + commit | small |
| 7 Completion loop | Opus `completion-auditor` | plan + diff from the base commit + verify commands | `DONE` / `GAPS` → fix tasks | yes, 1–3 short runs |
| 8 Report | orchestrator | auditor output | summary to you | small |

A **brief** is the only thing an implementer ever sees. It follows
[`skills/orchestrate/references/brief-template.md`](../skills/orchestrate/references/brief-template.md):
goal, relevant file paths, steps, acceptance tests, and a **Do NOT** list (no commits, no pushes, no
dependency upgrades, no files outside the task).

## 8. Lanes: choosing who does the work

A lane is a name mapped to a CLI and its settings. Your lanes live in
`~/.config/delegate-skills/config.json`. The default map is [`examples/lanes.json`](../examples/lanes.json):

| Lane | CLI | Model / effort | Writes? | Use for |
|---|---|---|---|---|
| `plan-check` | codex | gpt-6-astra, high | no | second opinion on plans |
| `complex` | codex | gpt-6-astra, high | yes | large or tricky tasks |
| `backend` | codex | default, medium | yes | server code, tests, migrations |
| `ui` | agy | gemini-3.8-flash-high | yes | pages, components, styling |
| `small` | claude | sonnet, medium | yes | small fixes, docs, lint |
| `fallback` | claude | sonnet, high | yes | when a lane fails twice or hits quota |
| `copilot-review` | copilot | default | no | optional extra opinion |

The plan says which lane each task uses. Rough rules:

- Touches many files, or the logic is hard → `complex`
- Normal server-side work → `backend`
- Anything visual → `ui`
- Under about 30 lines, or docs → `small`

## 9. Changing lanes and models

Three ways, from easiest to most manual:

1. **Ask Claude:** *"Use delegate-setup to change the ui lane to gemini-3.1-pro-high."* It shows you
   the new map and writes it only after you say yes.
2. **Edit `~/orchestra-skills/examples/lanes.json`**, then apply it:
   ```bash
   node ~/.claude/skills/delegate-setup/scripts/config.mjs validate ~/orchestra-skills/examples/lanes.json
   node ~/.claude/skills/delegate-setup/scripts/config.mjs write --scope global ~/orchestra-skills/examples/lanes.json
   ```
3. **Just once, for one task:** tell Claude *"send this one to the complex lane"*, or pass
   `--model` / `--effort` on that run only.

To see which models each CLI has: `node ~/.claude/skills/delegate-setup/scripts/discover.mjs`.

Per-project lanes: a repo can have `.delegate/config.json`, and each lane in it replaces the global
lane with the same name. Claude asks you before trusting a project file.

## 10. Permissions and safety

- **Implementers never commit or push.** The relay scripts don't commit, briefs forbid it, and
  `smoke-test.sh` checks for it. Only the orchestrator commits, after the tests pass.
- **Codex** writes inside the repo only (`workspace-write` sandbox).
- **Claude Sonnet lanes** use accept-edits mode and write inside the repo.
- **Antigravity** writes only in folders you allowed with `scripts/agy-allow.sh`. That script adds
  scoped rules to `~/.gemini/config/config.json` and keeps a timestamped backup. We never use
  `--dangerously-skip-permissions`.
- **Copilot** can only write with `--allow-all-tools`, which grants full access to every tool. That's
  why the default Copilot lane is read-only. Only turn writes on for a run if you accept that risk.
- **Repos without git history:** tell Claude. Briefs then forbid wide-reaching commands such as
  `composer update`, because nothing could undo them.

## 11. Saving tokens: what actually saves them

- **Typing happens on other quotas.** Codex runs on your ChatGPT plan, Antigravity on your Google
  quota, and Copilot on your GitHub plan. Only the `small` and `fallback` lanes use Claude, and they
  run on Sonnet.
- **Implementers never see your conversation.** A brief is about one page, not your whole chat.
- **Opus reads summaries, not files.** The Sonnet reviewer reads the diffs; Opus reads only its
  summary and the hunks it flags.
- **Big models run 3–4 times per feature** (plan, gate, optional second opinion, final audit), not
  once per file.
- **Resuming instead of restarting.** Follow-ups go to the same implementer session
  (`--session <id>`) with only the change needed.

### Measure it

```bash
~/orchestra-skills/scripts/token-report.sh "$TMPDIR"/delegate-relay/*   # every delegated run
```

It shows each run's lane, model, tokens, and which quota paid for it. Real numbers from the demo
test (see [TESTING.md](TESTING.md)):

```
RUN           LANE      TOOL    MODEL                 STATUS     IN TOKENS   OUT      USD     PAID BY
run-T1        backend   codex   default               completed  113,633     1,905    –       ChatGPT
run-T2        ui        agy     gemini-3.8-flash-high completed  –           –        –       Google
run-T3        small     claude  sonnet                completed  82,064      2,469    $0.077  Claude
```

The biggest job (T1, 113k tokens of code reading and writing) cost **zero Claude tokens**. The
Claude-side cost of the whole feature was the Opus gates (plan review ~10–13k, completion audit
~46k, per the subagent usage lines), the Sonnet reviewers (~17–18k each), and a few cents of Sonnet
for the docs task. Also run `/cost` at the end of the session and compare it with a session where
Opus did everything.

**Where the loop costs tokens:** each extra audit round is another Opus run of about 45k tokens.
That's why plans must have a clear Definition of Done: a precise plan usually passes in one round.

## 12. Using it without orchestrate

You can also delegate a single task directly:

> Use codex-delegate with --lane backend to add pagination to the orders API, then review and commit.

> Use agy-delegate --lane ui to restyle the login page.

> Have plan-reviewer check docs/plans/2026-09-21-billing.md.

---

## Cheat sheet

| I want to… | Say / run |
|---|---|
| Build a feature cheaply | *"Use orchestrate to build …"* |
| Deepest planning | `/model` → Fable, then orchestrate |
| Check a plan only | *"Have plan-reviewer check <plan path>"* |
| Get Astra's opinion on a plan | *"Send the plan to the plan-check lane"* |
| Send one task somewhere specific | *"Use codex-delegate --lane complex to …"* |
| See my lanes | `~/orchestra-skills/scripts/doctor.sh` |
| Test every lane | `~/orchestra-skills/scripts/smoke-test.sh` |
| See what each run cost and who paid | `~/orchestra-skills/scripts/token-report.sh "$TMPDIR"/delegate-relay/*` |
| Let Antigravity write in a folder | `~/orchestra-skills/scripts/agy-allow.sh <folder>` |
| Update orchestra-skills | `cd ~/orchestra-skills && git pull` |
| Update delegate-skills | re-run the `npx skills add amElnagdy/delegate-skills …` line |
