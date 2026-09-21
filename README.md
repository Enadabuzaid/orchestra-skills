# orchestra-skills

**Big models think. Cheap models type.** A Claude Code workflow that uses Fable, Opus and GPT-6
Astra only for planning and checking, and sends the actual coding to cheaper CLIs: Codex,
Antigravity (Gemini), Claude Sonnet and Copilot. Every plan is checked by Opus before any code is
written.

```
You ─▶ Claude Opus/Fable plans ─▶ Opus plan-reviewer: APPROVE? ─▶ short briefs
                                                                     │
          ┌──────────────────┬──────────────────┬───────────────────┘
          ▼                  ▼                  ▼
   Codex / GPT-6 Astra   Antigravity       Claude Sonnet
   (backend, complex)    (ui)              (small, fallback)
          └──────────────────┴────────┬─────────┘
                                      ▼
                   Sonnet diff-reviewer ─▶ Claude runs tests + commits
                                      ▼
            Opus completion-auditor: every plan item done? verify commands pass?
                 DONE ─▶ report to you        GAPS ─▶ fix tasks ─▶ lanes ─▶ audit again
```

## Why

In a normal session the most expensive model reads every file and writes every line. Here:

- **Coding runs on other quotas:** your ChatGPT plan (Codex), Google (Antigravity), or cheap Sonnet.
- **Implementers never see your chat.** They get a one-page brief.
- **Opus reads summaries, not diffs.** Sonnet does the line-by-line review.
- **Big models run 3–4 times per feature,** not once per file.
- **Quality stays high:** an Opus gate on every plan, a review of every diff, and tests re-run before
  every commit. At the end an Opus **completion loop** checks every plan item and runs the plan's
  verify commands, and missing work goes back to the implementers until it returns `DONE`.
  Implementers never commit.

## Who does what

| Job | Model | Lane / agent |
|---|---|---|
| Plan | Claude Fable 5.1 / Opus 5 | your session |
| Check the plan (mandatory) | Claude Opus 5 | `plan-reviewer` agent |
| Second opinion (optional) | GPT-6 Astra | `plan-check` lane (read-only) |
| Large / tricky tasks | GPT-6 Astra | `complex` lane |
| Backend tasks | Codex default | `backend` lane |
| UI tasks | Gemini 3.8 Flash (Antigravity) | `ui` lane |
| Small fixes and docs | Claude Sonnet 5 | `small` lane |
| When a lane fails or hits quota | Claude Sonnet 5 (high) | `fallback` lane |
| Review each diff | Claude Sonnet 5 | `diff-reviewer` agent |
| Decide when it's finished (loops until DONE) | Claude Opus 5 | `completion-auditor` agent |

## Install (5 minutes)

```bash
# 1. The implementer skills (by amElnagdy — we build on them, not fork them)
npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \
  --skill codex-delegate --skill agy-delegate --skill claude-delegate \
  --skill copilot-delegate --skill delegate-setup

# 2. This repo
git clone https://github.com/Enadabuzaid/orchestra-skills ~/orchestra-skills
~/orchestra-skills/install.sh

# 3. Let Antigravity write in your projects folder (only if you use the ui lane)
~/orchestra-skills/scripts/agy-allow.sh ~/Code

# 4. Check everything, then restart Claude Code
~/orchestra-skills/scripts/doctor.sh
~/orchestra-skills/scripts/smoke-test.sh
```

Log in to each CLI once first (`codex login`, run `agy` once, `gh auth login`). You don't need every
CLI: move a lane to a CLI you have (see the [guide](docs/GUIDE.md#9-changing-lanes-and-models)).

## Use

In Claude Code, on Opus (or Fable for hard features):

> Use orchestrate to add CSV export to the reports page.

Claude plans, gets `APPROVE` from Opus, sends tasks to the lanes, has each diff reviewed, re-runs the
tests and commits task by task. Then Opus checks every plan item and runs the verify commands,
sending any gaps back to the implementers until everything is `DONE`, and Claude reports what was
built and how it was verified. You review `git log` and push.

## Tested

- `scripts/smoke-test.sh` sends a real coding task to every lane and checks the result itself
  (code added, tests green, no commits).
- A full end-to-end run on `examples/demo-app` (3 tasks, 3 different implementers) is written up
  in [docs/TESTING.md](docs/TESTING.md#reference-run-2026-09-21). The Opus gate rejected the first
  plan with 5 real problems before any code was written.

## Docs

- **[docs/GUIDE.md](docs/GUIDE.md)**: the complete guide, from install and first feature to lanes,
  models, permissions and token savings
- [docs/TESTING.md](docs/TESTING.md): doctor, lane smoke test and end-to-end test
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): common failures and fixes

## What's in the repo

| Path | Purpose |
|---|---|
| `skills/orchestrate/` | The 8-stage workflow skill plus the plan and brief templates |
| `agents/plan-reviewer.md` | Opus plan gate: `APPROVE` or numbered fixes |
| `agents/diff-reviewer.md` | Sonnet per-task reviewer: `PASS` / `FAIL` |
| `agents/completion-auditor.md` | Opus completion gate: `DONE` / `GAPS` |
| `CLAUDE.snippet.md` | Rules added to `~/.claude/CLAUDE.md` |
| `examples/lanes.json` | The default lane map |
| `examples/demo-app/` | A tiny app for the end-to-end test |
| `install.sh` | Links everything into `~/.claude` (safe to re-run) |
| `scripts/doctor.sh` | Checks the setup (changes nothing) |
| `scripts/smoke-test.sh` | Real test of every lane |
| `scripts/agy-allow.sh` | Scoped Antigravity write permission for a folder |
| `scripts/token-report.sh` | Tokens per delegated run, and which quota paid |

## Credits

Implementer relays: [amElnagdy/delegate-skills](https://github.com/amElnagdy/delegate-skills) (MIT).

MIT licensed.
