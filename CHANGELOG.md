# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org).
Install a specific version with `git checkout vX.Y.Z`, or `npx skills add Enadabuzaid/orchestra-skills@vX.Y.Z`.

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
