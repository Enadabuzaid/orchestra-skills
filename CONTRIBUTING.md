# Contributing

Orchestra is an AI engineering router: it decides how much intelligence, context and money a coding
task deserves. Contributions that keep that promise are welcome.

## Principles (what a change must respect)

1. **Nothing expensive before the router.** Tiny and small work must never reach Fable, Opus or Astra.
2. **Minimum sufficient context.** Every model gets a card, never the conversation. Cards must pass
   `scripts/brief-check.sh`.
3. **Roles, not vendors.** The workflow asks for a role; the policy picks the model. Never hard-code a
   model in a skill or agent file.
4. **Planner ≠ Builder ≠ Reviewer.** Reviews come from a different model than the builder.
5. **Evidence over claims.** A gate passes when the orchestrator ran it, not when a worker said so.
6. **Zero-quota tests must stay zero-quota.** `scripts/self-test.sh` runs in CI on macOS and Linux
   with fake tools; anything that needs a real model belongs in `smoke-test.sh` or `e2e-test.sh`.

## Before you open a PR

```bash
scripts/self-test.sh            # must pass (no model calls)
scripts/doctor.sh               # your setup
scripts/smoke-test.sh role:<role>   # for changes that touch a role or relay path (uses real quota)
```

Scripts must work on **macOS bash 3.2** as well as Linux bash 5 (no `${arr[@]}` on empty arrays under
`set -u`, no `mapfile`, no GNU-only `sed`). CI runs both.

## Layout

| Path | What |
|---|---|
| `skills/orchestrate/` | the Claude Code workflow (subagents) |
| `skills/orchestrate-portable/` | the same workflow for Codex and other apps |
| `agents/` | subagent definitions: router, lane-runner, reviewer, auditor |
| `examples/orchestra.json` | the default policy: models, roles, routing, budget |
| `scripts/orchestra.mjs` | the policy engine (Node built-ins only, no dependencies) |
| `scripts/*.sh` | install, doctor, tests, card check, token report |
| `docs/` | guides; start with `POLICY.md` and `ARCHITECTURE.md` |

## Adding a model or tool

1. If delegate-skills has a relay for it (`npx skills add amElnagdy/delegate-skills --list`), no code
   is needed: add it under `models` in `examples/orchestra.json` and to the roles' fallback chains.
2. Run `scripts/smoke-test.sh role:<role>` with it as primary, and paste the result in the PR.
3. Document its login/install in `docs/LANES.md` ("Adding Kimi or DeepSeek" shows the pattern).

## Commits and PRs

- Plain conventional messages (`feat:`, `fix:`, `docs:`, `test:`), no attribution trailers.
- Say what you tested and how. If a test needed real quota, say which tools and what it cost.
- Versions follow semver; `CHANGELOG.md` gets a line per user-visible change.

## Reporting a problem

Open an issue with: the command, the output, `scripts/doctor.sh` output, your OS, and (if a run
misbehaved) the `result.json` of the relay run. Never paste API keys, tokens or `.env` contents.
