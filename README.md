# orchestra-skills

**An AI engineering router: it decides how much intelligence, context and money a coding task deserves.** A Claude Code workflow that uses Fable, Opus and GPT-6
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

## Why: the token model

Most tokens in a coding session go to **typing** (reading files, writing code, running tests) and to
**repeated context** (the same conversation sent to every call). Orchestra cuts both:

| Lever | What it does | Measured |
|---|---|---|
| **Route before anything expensive** | a Haiku router classifies tiny / small / feature / complex; each level gets only its process | "change one error message": route → card → Sonnet → test → commit, **0 expensive calls, $0.25, 91s** |
| **Minimum sufficient context** | builders and reviewers get one short card, never the conversation; retries send only the failing check | cards are 100–250 words; `brief-check.sh` rejects leaks |
| **ROLE → MODEL with fallbacks** | "I need a backend builder" → Codex → Kimi → DeepSeek → Sonnet, by live availability and quota | Codex out of quota → backend fell back to Sonnet automatically |
| **A budget of expensive calls** | a normal feature = Fable once + Opus once; a complex one adds one second opinion | `orchestra budget spend` refuses the 4th expensive call |
| **Planner ≠ Builder ≠ Reviewer** | independent review by another model; second opinions from another family | Astra found a real date bug in a Fable plan before any code |
| **Other subscriptions do the typing** | Codex on ChatGPT, Antigravity on Google, Kimi/DeepSeek on theirs | a 113k-token backend task cost 0 Claude tokens |

Full results, including the failures found along the way: [docs/TESTING.md](docs/TESTING.md).

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
| Run the approved plan: briefs, lanes, reviews, commits | Claude Sonnet 5 | `lane-runner` agent |
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

New here? Read **[docs/QUICKSTART.md](docs/QUICKSTART.md)**. In Claude Code, inside your project, on
Opus (or Fable for hard features):

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

- **[docs/POLICY.md](docs/POLICY.md)**: the Orchestra policy: routing levels, ROLE → MODEL with fallbacks, token budget, compact cards, run metrics
- **[docs/ROADMAP.md](docs/ROADMAP.md)**: v0.5 Token Intelligence → v0.6 More models → v0.7 Smart context
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**: the design in one page: router → planner lane → different-AI review → job lanes with task cards → final audit
- **[docs/QUICKSTART.md](docs/QUICKSTART.md)**: start here. "I opened Claude Code, what now?" in one page
- **[docs/CODEX.md](docs/CODEX.md)**: run everything from the **Codex app** (Astra plans, Claude Fable/Opus check, lanes build)
- **[docs/LANES.md](docs/LANES.md)**: change who does what (backend, ui, checkers, "Codex hit its limit"), one command each
- **[docs/EXAMPLE.md](docs/EXAMPLE.md)**: a real example ("make sure patient login and register work"): where to type, what you'll see at each step, and who pays
- **[docs/GUIDE.md](docs/GUIDE.md)**: the complete guide, from install and first feature to lanes,
  models, permissions and token savings
- [docs/TESTING.md](docs/TESTING.md): **test it yourself, step by step** (doctor → lane smoke test → automated end-to-end → watch it live → token check), with recorded results
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): common failures and fixes

## What's in the repo

| Path | Purpose |
|---|---|
| `skills/orchestrate-portable/` | The same workflow for the Codex app and other tools without Claude subagents |
| `skills/orchestrate/` | The 8-stage workflow skill plus the plan and brief templates |
| `agents/plan-reviewer.md` | Opus plan gate: `APPROVE` or numbered fixes |
| `agents/diff-reviewer.md` | Sonnet per-task reviewer: `PASS` / `FAIL` |
| `agents/completion-auditor.md` | Opus completion gate: `DONE` / `GAPS` |
| `agents/lane-runner.md` | Sonnet runner for the approved plan (briefs → lanes → review → commit) |
| `CLAUDE.snippet.md` | Rules added to `~/.claude/CLAUDE.md` |
| `examples/lanes.json` | The default lane map |
| `examples/demo-app/` | A tiny app for the end-to-end test |
| `install.sh` | Links everything into `~/.claude` (safe to re-run) |
| `scripts/orchestra` | The policy engine: `roles`, `resolve`, `set`, `route`, `budget`, `exhausted`, `metrics`, `edit`, `undo` |
| `examples/orchestra.json` | The default policy (models, roles with fallbacks, routing, budget) |
| `scripts/lanes.sh` | Older per-lane config for running single relays by hand |
| `scripts/brief-check.sh` | Rejects task cards that are incomplete, too long, or leak context |
| `agents/task-router.md` | Haiku router: simple / medium / complex / very-complex |
| `scripts/doctor.sh` | Checks the setup (changes nothing) |
| `scripts/smoke-test.sh` | Real test of every lane |
| `scripts/agy-allow.sh` | Scoped Antigravity write permission for a folder |
| `scripts/token-report.sh` | Tokens per delegated run, and which quota paid |
| `scripts/e2e-test.sh` | Unattended full-workflow test on the demo app, checked by the script |

## Author

**Enad Abuzaid** · [@Enadabuzaid](https://github.com/Enadabuzaid)

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Versions: [CHANGELOG.md](CHANGELOG.md).

## Credits

The implementer relays come from [amElnagdy/delegate-skills](https://github.com/amElnagdy/delegate-skills)
(MIT). orchestra-skills builds on them and doesn't fork them.

## License

[MIT](LICENSE) © 2026 Enad Abuzaid
