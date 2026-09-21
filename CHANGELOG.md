# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org).
Install a specific version with `git checkout vX.Y.Z`, or `npx skills add Enadabuzaid/orchestra-skills@vX.Y.Z`.

## [0.5.1] - 2026-09-21 — Every subscription, no poisoned cache

Driven by the first unattended v0.5 end-to-end run (16/17 checks, `DONE`, but 171 minutes and every
builder on Claude). Details in `docs/TESTING.md`.

### Fixed
- **A failed CLI discovery made every role `NONE AVAILABLE` for 15 minutes.** The empty result was
  cached. Now a failed or empty probe is never cached: the last good result is kept, and without one
  a PATH check is used. `orchestra roles` says when it's running on stale or fallback data;
  `orchestra resolve` hints at `--refresh`; `doctor.sh` always re-probes and prints why each model
  in an unavailable chain was skipped.
- **Read-only roles could land on a relay that can't enforce read-only** (Kimi's has no
  `--read-only`), and flags a relay doesn't accept (`--effort` for Kimi) were passed. The engine now
  reads each relay's accepted flags and skips or omits accordingly.
- `orchestra undo` had nothing to restore after the first `orchestra set` on a fresh machine.
- `orchestra metrics <run>` finds the relay runs from the run id when `budget start` had no `--dir`.
- `completion-auditor` names roles (`backend|frontend|tests|…`), not the pre-v0.5 lane names.

### Added
- **`orchestra check`**: validates a policy (models exist; read-only roles only use relays with
  `--read-only`; writing roles never use a read-only-only tool such as Copilot; routing refers to
  existing roles). Run by `doctor.sh` and the self-test.
- **Copilot** as a read-only reviewer (`review`, `ui-review`, `security-review`, `planner-light`
  fallbacks), and the **free OpenCode tier** (`opencode-free` = `opencode/big-pickle`, smoke-tested)
  as the last stop before Sonnet in every builder chain, so typing stays off paid quotas when
  Codex, Antigravity, Kimi and DeepSeek are all out. GPT-5.6 Luna also precedes Sonnet everywhere.
- `doctor.sh <project>`: per-project readiness (git, clean tree, detected test command, Antigravity
  write rule) so orchestrate can be used in any project after one install.
- `install.sh` links `~/orchestra-skills` to the checkout when it lives elsewhere, always installs the
  `orchestra` command in `~/.local/bin`, and lists the Kimi and OpenCode relays.
- Self-test: discovery failure handling, relay-flag awareness, `orchestra check`, `undo`, the
  installer's `~/orchestra-skills` link, `metrics` without `--dir`.

### Changed
- **Haiku no longer builds.** As the `docs` builder it looped for 650k tokens on a README in the
  recorded run. It stays in read-only chains (reviews) and routes.
- Kimi is out of the `review` chain (no read-only mode); it still builds.
- Docs use the v0.5 vocabulary throughout (tiny / small / feature / complex, roles not lanes);
  README, QUICKSTART, POLICY, ARCHITECTURE, TESTING and TROUBLESHOOTING updated; CLAUDE.md and
  AGENTS.md snippets no longer mention the pre-v0.5 route names.

## [0.5.0] - 2026-09-21 — Token Intelligence

### Added
- **Task router before anything expensive**: tiny / small / feature / complex with `Hard` and
  `Areas`. "Change button text" is route → card → builder → test → done.
- **Model policy** (`examples/orchestra.json`, `scripts/orchestra`): ROLE → MODEL with ordered
  fallbacks, live availability (installed, logged in, model offered, quota), `orchestra exhausted`,
  builder ≠ reviewer (`--not-model`), different family for second opinions (`--not-family`),
  `--cheap-only` when the budget is used.
- **Token budget**: `expensive_calls`, per-kind `max_calls`, `only_for` for second opinions,
  `max_retries`, card token limits. `orchestra budget spend` records each call first and refuses
  over-budget ones. A normal feature = Fable once + Opus once.
- **Compact cards**: task card / delta retry / review card formats; `brief-check.sh` enforces
  sections, token limits and no leaked context.
- **Delta retry**: only the failing check, same session, "already accepted" list.
- **Run metrics**: `orchestra metrics <run>`.
- `docs/POLICY.md`, `docs/ROADMAP.md`. `smoke-test.sh role:<role>` tests a role through the policy.
- Earlier in this release:
- **Task router** (`agents/task-router.md`, Haiku): simple / medium / complex / very-complex. Simple
  work gets one task card and no plan; medium gets a plan but no architecture review; only
  complex+ pays for the review.
- **Planner lanes**: `planner` (Fable), `planner-hard` (Opus, very-complex), and the fallback chain
  `planner-fallback` (Opus) → `planner-alt` (GPT-6 Astra). Planning runs read-only in a lane, so the
  main session can run on Sonnet.
- **Architecture review by a different model family**: `architecture-review` (Astra), or
  `architecture-review-alt` (Fable) when the planner was the same family. The revise loop reuses the
  planner's session. Tested: Astra caught a real `Date.UTC` year-0–99 bug in a Fable plan; the
  revised plan was approved.
- **Context isolation**: a strict task-card format (TASK / Goal / Files / Contract / Rules /
  Acceptance / Do not) and `scripts/brief-check.sh`, which rejects cards that are incomplete, over
  450 words, or show leaked context.
- **Job lanes, not vendors**: `backend`, `frontend`, `tests`, `refactor`, `debug`, `docs`,
  `code-review`, `ui-review`, `security-review`, `final-audit`, `small`, `fallback`
  (`references/lanes.md`). Also `lanes.sh resolve <job>` (accepts the older names), a `debug` step
  for failing gates, and `<job>-fallback` chains for every job.
- `docs/ARCHITECTURE.md`.

### Fixed
- **Implementers no longer orchestrate.** Workers load the same global rules as orchestrators, and
  in testing a Codex worker started orchestrating its own task. The rules now apply only to the
  top-level session, and every task card says "You are the implementer…" (enforced by
  `brief-check.sh`).

### Changed
- Presets use job names only (no vendor-named lanes). The default preset is the ORCHESTRA layout.
  Older lane names (`ui`, `review`, `ui-check`, `plan-check`, `plan-gate`, `done-gate`) are still
  resolved.

## [0.4.0] - 2026-09-21

### Added
- **`orchestrate-portable` skill**: the workflow for the Codex app/CLI and other tools without
  Claude Code subagents. The session plans (e.g. GPT-6 Astra); Claude approves the plan and decides
  DONE through the read-only **`plan-gate`** and **`done-gate`** lanes. For the done check,
  Codex runs the Verify commands and Claude reads the output, diff and status.
- `install.sh` links it into `~/.codex/skills` and adds rules to `~/.codex/AGENTS.md`.
- `examples/lanes-codex-orchestrator.json`: plan-gate → Fable, done-gate → Opus, backend → Codex
  GPT-5.6-Luna, ui → Codex, ui-check → Antigravity.
- `scripts/e2e-test.sh --codex`: the end-to-end test with Codex as the orchestrator.
- `docs/CODEX.md`.

## [0.3.1] - 2026-09-21

### Added
- `scripts/lanes.sh`: change lanes with one command: `set`, `remove`, `replace <tool> <tool>` (for
  when a tool hits its quota), `use <preset>`, `presets`, `models <tool>`, `undo`. Every change is
  validated and backed up.
- `docs/LANES.md`: every common change with its exact command.

## [0.3.0] - 2026-09-21

### Added
- **Check lanes**: a read-only lane named `<lane>-check` reviews that lane's work (a second tool's
  opinion) before the `lane-runner` commits it. Findings go back to the implementer; the check is
  advisory.
- `examples/lanes-codex-frontend.json`: backend → Sonnet, ui → Codex, ui-check → Antigravity.
- Guide §13: using other apps (Codex, Cursor) as the orchestrator. What's portable, and what isn't yet.

### Changed
- The `lane-runner`, the skill and the CLAUDE.md rules read the lane map from config instead of
  assuming lane → tool, so user changes to the lanes take effect everywhere.

## [0.2.1] - 2026-09-21

### Added
- `docs/QUICKSTART.md`: one page from "I opened Claude Code" to a finished feature.
- `docs/EXAMPLE.md`: a real run on a Laravel app (patient login/register), with the plan, gates,
  commits and token numbers.

### Fixed
- Claude runs (lanes, `e2e-test.sh`, `smoke-test.sh`) use the claude.ai subscription even when an
  unrelated `ANTHROPIC_API_KEY` is set; `doctor.sh` reports which billing Claude uses.
- `token-report.sh` labels runs by task.
- The global CLAUDE.md rules now point to the `lane-runner`.

## [0.2.0] - 2026-09-21

### Added
- `completion-auditor` agent (Opus): a feature is finished only when it returns `DONE`; gaps
  become fix tasks, up to 3 rounds.
- Plan template with **Definition of Done** and **Verify** sections, plus a Status column.
- `plan-reviewer` now rejects plans whose finish can't be proven.
- `scripts/token-report.sh`: tokens per delegated run, and which quota paid for it.
- `scripts/e2e-test.sh`: runs the whole workflow unattended on the demo app and checks the result.
- Stage 8: a factual final report to the user.
- `lane-runner` agent (Sonnet): runs Stages 3–6 (briefs, dispatch, diff review, commits), so Opus
  only plans and runs the gates. Measured in the end-to-end test: without it, the Opus
  orchestrator was ~92% of the Claude cost.

### Fixed
- Headless runs (`claude -p`): Claude ended its turn while relays were running, which killed them
  (`aborted … SIGTERM`). The skill now blocks until every `result.json` exists.
- Relay logs now go to `$TMPDIR/orchestrate/<repo>/<task>`, never inside the repo.

## [0.1.0] - 2026-09-21

### Added
- `orchestrate` skill (plan → Opus gate → lanes → Sonnet review → land → Opus audit).
- `plan-reviewer` (Opus) and `diff-reviewer` (Sonnet) agents.
- 7-lane map: `plan-check`/`complex` (GPT-6 Astra), `backend` (Codex), `ui` (Antigravity),
  `small`/`fallback` (Claude Sonnet), `copilot-review` (read-only).
- `install.sh`, `scripts/doctor.sh`, `scripts/smoke-test.sh`, `scripts/agy-allow.sh`, demo app, docs.
