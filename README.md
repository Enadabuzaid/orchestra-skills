# orchestra-skills

**An AI engineering router: it decides how much intelligence, context and money a coding task
deserves.** Thinking (planning, the second opinion, the final audit) goes to the strongest models,
Claude Fable, Claude Opus and GPT-6 Astra, and is budgeted. Typing (code, tests, docs, reviews) goes
to the cheapest model that is available right now across every subscription you have: Codex and
GPT-5.6 Luna on ChatGPT, Antigravity (Gemini) on Google, Kimi, DeepSeek, OpenCode's free tier,
Copilot for read-only reviews, and Claude Sonnet last. Works in any project after one install.

```
You ─▶ task-router (Haiku): tiny | small | feature | complex
          │
          ├─ tiny ──────▶ one card ─▶ cheapest builder ─▶ test ─▶ commit           (0 expensive calls)
          ├─ small ─────▶ light plan (Sonnet) ─▶ builders ─▶ review ─▶ Verify       (0 expensive calls)
          ├─ feature ───▶ Fable plans ─▶ lane-runner (Sonnet) ─▶ Opus final audit   (2 expensive calls)
          └─ complex ───▶ Fable/Opus plan ─▶ Astra second opinion ─▶ … ─▶ Opus audit (≤3 expensive calls)

   lane-runner, per task:  card ─▶ orchestra resolve <role> ─▶ builder ─▶ gate ─▶ review by a
                           different model ─▶ delta retry if needed ─▶ one commit
```

## Why: the token model

Most tokens in a coding session go to **typing** (reading files, writing code, running tests) and to
**repeated context** (the same conversation sent to every call). Orchestra cuts both:

| Lever | What it does | Measured |
|---|---|---|
| **Route before anything expensive** | a Haiku router classifies tiny / small / feature / complex; each level gets only its process | "change one error message": route → card → Sonnet → test → commit, **0 expensive calls, $0.25, 91s** |
| **Minimum sufficient context** | builders and reviewers get one short card, never the conversation; retries send only the failing check | cards are 100–250 words; `brief-check.sh` rejects leaks |
| **ROLE → MODEL with fallbacks** | "I need a backend builder" → Codex → Kimi → DeepSeek → Luna → OpenCode free → Sonnet, by live availability and quota | Codex out of quota → backend fell back automatically, twice, in the recorded runs |
| **A budget of expensive calls** | a normal feature = Fable once + Opus once; a complex one adds one second opinion | `orchestra budget spend` refuses the 4th expensive call |
| **Planner ≠ Builder ≠ Reviewer** | independent review by another model; second opinions from another family | Astra found a real date bug in a Fable plan before any code |
| **Other subscriptions do the typing** | Codex on ChatGPT, Antigravity on Google, Kimi/DeepSeek on theirs, OpenCode's free tier at $0 | a 113k-token backend task cost 0 Claude tokens |
| **Never stuck on one quota** | a tool that hits its limit is marked exhausted (`orchestra exhausted codex --until 21:34`) and every role skips it until then | the v0.5 end-to-end run finished with Codex and Copilot both out of quota |

Full results, including the failures found along the way: [docs/TESTING.md](docs/TESTING.md).

## Who does what (default policy)

Every job is a **role** with an ordered chain; the first model that is installed, logged in, offered
by its CLI and not out of quota does the job. See it live with `orchestra roles`.

| | Role | Chain (primary → fallbacks) |
|---|---|---|
| **Thinking** | `planner` (feature) | Fable → Astra → Opus |
| | `planner-hard` (complex + Hard) | Opus → Fable → Astra |
| | `planner-light` (small) | Sonnet → Luna → Copilot → Haiku |
| | `architecture` (second opinion, other family) | Astra → Opus |
| | `final-audit` | Opus |
| **Typing** | `backend` | Codex → Kimi → DeepSeek → Luna → OpenCode free → Sonnet |
| | `frontend` | Antigravity → Codex → Kimi → Luna → OpenCode free → Sonnet |
| | `tests` | Kimi → DeepSeek → Luna → Antigravity → OpenCode free → Sonnet |
| | `refactor` | Kimi → Codex → Luna → OpenCode free → Sonnet |
| | `debug` | Codex → Luna → OpenCode free → Sonnet |
| | `docs`, `small` | DeepSeek → … → OpenCode free → Sonnet |
| **Checking** (read-only) | `review` (every task) | DeepSeek → Luna → OpenCode free → Copilot → Haiku → Sonnet |
| | `ui-review` (frontend tasks) | Codex → Luna → Copilot → Sonnet |
| | `security-review` (sensitive tasks) | Astra → Copilot → Sonnet |

Haiku never builds (in the recorded run it looped for 650k tokens on a README); Copilot only reviews
(headless writes need `--allow-all-tools`); Kimi builds but never reviews (its relay has no
read-only mode). `orchestra check` enforces these rules on any policy you edit.

## Install (5 minutes, once per machine)

```bash
# 1. The implementer relays (by amElnagdy — we build on them, not fork them). Install the ones for
#    the CLIs you have; the policy skips the rest.
npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \
  --skill delegate-setup --skill claude-delegate --skill codex-delegate --skill agy-delegate \
  --skill copilot-delegate --skill kimi-delegate --skill opencode-delegate

# 2. This repo (any folder works; the installer links ~/orchestra-skills to it)
git clone https://github.com/Enadabuzaid/orchestra-skills ~/orchestra-skills
~/orchestra-skills/install.sh

# 3. Check the machine, then restart Claude Code
~/orchestra-skills/scripts/doctor.sh
```

Log in to each CLI once (`codex login`, run `agy` once, `copilot login`, `kimi`, `opencode auth login`).
You don't need every CLI: a role whose whole chain is unavailable shows `NONE AVAILABLE` in the
doctor, with the reason for each model and the `orchestra set` command to change it.

## Use it in any project

Nothing is installed inside a project. Once per project:

```bash
cd ~/Code/my-project
~/orchestra-skills/scripts/doctor.sh .                                  # git? clean tree? test command? Antigravity allowed?
~/orchestra-skills/scripts/agy-allow.sh . --tests "npm test"            # only if the doctor asks for it
```

Then in Claude Code, inside the project, on Sonnet (the session only coordinates):

> Use orchestrate to add CSV export to the reports page.

The router picks the level, the planner writes `docs/plans/<date>-<feature>.md`, the lane-runner
builds task by task with one commit each, and the Opus auditor decides `DONE`. You read `git log` and
push. New here? Read **[docs/QUICKSTART.md](docs/QUICKSTART.md)**.

## Tested

- `scripts/self-test.sh`: 10 zero-quota checks (installer, doctor, cards, the policy engine with
  fake tools, discovery failure handling, budget), run by CI on macOS and Linux.
- `scripts/smoke-test.sh role:backend role:review …`: a real coding task through the model each role
  resolves to right now; the script checks the files, the tests and that nothing was committed.
- `scripts/e2e-test.sh`: a fresh, unattended Claude Code session builds a 3-task feature on the demo
  app with `orchestrate`; the script checks the result itself (17 checks). Recorded runs, with what
  each one found, are in [docs/TESTING.md](docs/TESTING.md#recorded-results).

## Docs

- **[docs/QUICKSTART.md](docs/QUICKSTART.md)**: start here. Install once, then use it in any project
- **[docs/POLICY.md](docs/POLICY.md)**: the Orchestra policy: routing levels, ROLE → MODEL with fallbacks, token budget, compact cards, run metrics
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**: the design in one page
- **[docs/TESTING.md](docs/TESTING.md)**: test it yourself, step by step, with recorded results
- **[docs/CODEX.md](docs/CODEX.md)**: run everything from the Codex app instead of Claude Code
- **[docs/EXAMPLE.md](docs/EXAMPLE.md)**: a real example on a Laravel app: where to type, what you'll see, who pays
- **[docs/GUIDE.md](docs/GUIDE.md)**: the complete guide (some sections still use the older lane vocabulary)
- [docs/LANES.md](docs/LANES.md): the older per-lane config, still used for running single relays by hand
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): common failures and fixes
- [docs/ROADMAP.md](docs/ROADMAP.md): what's next

## What's in the repo

| Path | Purpose |
|---|---|
| `skills/orchestrate/` | The workflow skill for Claude Code, plus the policy, card and plan references |
| `skills/orchestrate-portable/` | The same workflow for the Codex app and other tools without Claude subagents |
| `agents/task-router.md` | Haiku router: tiny / small / feature / complex |
| `agents/lane-runner.md` | Sonnet build coordinator: cards → builders → gates → reviews → commits |
| `agents/plan-reviewer.md` | Opus plan gate (fallback second opinion): `APPROVE` or numbered fixes |
| `agents/diff-reviewer.md` | Sonnet per-task reviewer: `PASS` / `FAIL` |
| `agents/completion-auditor.md` | Opus completion gate: `DONE` / `GAPS` |
| `examples/orchestra.json` | The default policy (models, roles with fallbacks, routing, budget) |
| `scripts/orchestra` | The policy engine: `roles`, `resolve`, `set`, `check`, `route`, `budget`, `exhausted`, `metrics`, `edit`, `undo` |
| `scripts/brief-check.sh` | Rejects task cards that are incomplete, too long, or leak context |
| `scripts/doctor.sh` | Checks the machine, and with a path, the project (changes nothing) |
| `scripts/smoke-test.sh` | A real task through any role or lane |
| `scripts/e2e-test.sh` | Unattended full-workflow test on the demo app, checked by the script |
| `scripts/self-test.sh` | Zero-quota checks (CI) |
| `scripts/token-report.sh` | Tokens per delegated run, and which quota paid |
| `scripts/agy-allow.sh` | Scoped Antigravity write permission for a folder |
| `scripts/lanes.sh`, `examples/lanes*.json` | Older per-lane config for running single relays by hand |
| `CLAUDE.snippet.md`, `CODEX.snippet.md` | Rules added to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` |
| `examples/demo-app/` | A tiny app for the end-to-end test |
| `install.sh` | Links everything into `~/.claude`, `~/.codex` and `~/.local/bin` (safe to re-run) |

## Author

**Enad Abuzaid** · [@Enadabuzaid](https://github.com/Enadabuzaid)

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Versions: [CHANGELOG.md](CHANGELOG.md).

## Credits

The implementer relays come from [amElnagdy/delegate-skills](https://github.com/amElnagdy/delegate-skills)
(MIT). orchestra-skills builds on them and doesn't fork them.

## License

[MIT](LICENSE) © 2026 Enad Abuzaid
