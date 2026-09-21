# Changing who does what (lanes)

**A lane is a job, not a vendor.** The workflow says "send this to `backend`" or "have
`code-review` check it". Which tool and model does each job is your choice, and you can change it
with one command. Every change is validated and backed up first, and `undo` brings the previous
setup back.

All commands use `~/orchestra-skills/scripts/lanes.sh`. An alias makes it shorter:

```bash
echo "alias lanes='~/orchestra-skills/scripts/lanes.sh'" >> ~/.zshrc && source ~/.zshrc
```

## The jobs

| Job | What it does | Default tool (model) |
|---|---|---|
| `planner` | writes plans for medium and complex work | Claude (Fable) |
| `planner-hard` | writes plans for very-complex work | Claude (Opus) |
| `planner-fallback` → `planner-alt` | next planners if the one before is out of quota | Claude (Opus) → Codex (GPT-6 Astra) |
| `architecture-review` | challenges hard plans; must be **a different family** from the planner | Codex (GPT-6 Astra) |
| `architecture-review-alt` | the challenger when the planner is the same family as `architecture-review` | Claude (Fable) |
| `backend` | server code | Codex |
| `frontend` | pages and components | Antigravity (Gemini 3.8 Flash) |
| `tests` | writes/extends tests | Codex (GPT-5.6-Luna) |
| `refactor` | behaviour-preserving restructuring | Codex |
| `debug` | fixes a failing gate from its output | Codex (high effort) |
| `docs` | README / API docs | Claude (Haiku) |
| `code-review` | reviews **every** task's diff | Claude (Haiku) |
| `ui-review` | reviews **frontend** diffs | Codex (Luna) |
| `security-review` | reviews **sensitive** diffs (auth, payments, permissions, uploads, SQL, crypto) | Claude (Sonnet) |
| `final-audit` | DONE/GAPS in the Codex workflow (Claude Code uses its Opus auditor agent) | Claude (Opus) |
| `small` | one-card quick fixes | Claude (Sonnet) |
| `fallback` | last resort when a job fails | Claude (Sonnet, high) |

A job you don't configure is skipped (reviews) or handled by the runner itself. For any job, a lane
called `<job>-fallback` is tried before the global `fallback`.

## See the current setup

```bash
lanes                       # the table: job, tool, model, effort, read-only?, who pays
lanes resolve frontend      # which lane/tool/model does a job right now
```

## Change a job

```bash
lanes set backend codex effort=medium
lanes set backend claude model=sonnet
lanes set frontend codex
lanes set frontend agy model=gemini-3.1-pro-high
lanes set tests codex model=gpt-5.6-luna
lanes set docs claude model=haiku
lanes set code-review claude model=haiku readonly
lanes set security-review claude model=opus readonly
lanes set planner claude model=opus readonly         # plan with Opus instead of Fable
lanes set architecture-review codex model=gpt-6-astra readonly
lanes remove ui-review                               # no UI review
```

The tools: `codex` (ChatGPT plan), `agy` (Antigravity, Google), `claude` (Claude plan), `copilot`
(GitHub), plus anything delegate-skills supports, such as `kimi` or `opencode`. See a tool's
models with `lanes models <tool>`.

Review, planner, architecture-review and final-audit lanes should be **read-only** (`readonly`).

## A tool hit its limit

```bash
lanes replace codex claude model=sonnet    # every Codex job moves to Sonnet
lanes undo                                 # quota back: restore
```

You don't *have* to: a job that fails because of quota moves to `<job>-fallback` or `fallback`
automatically. `replace` just saves the failed first attempt while a tool is out for a while.

## Ready-made setups

```bash
lanes presets
lanes use default               # the ORCHESTRA layout above
lanes use codex-frontend        # backend → Sonnet, frontend → Codex, ui-review → Antigravity
lanes use codex-orchestrator    # for running from the Codex app: backend → Codex Luna, frontend → Codex
```

Your own preset: save it as `examples/lanes-<name>.json`, then `lanes use <name>`.

## Adding Kimi or DeepSeek

Lanes are jobs, so a new model is just a new mapping.

**Kimi** (tests, for example):
1. Install the Kimi Code CLI and log in with your Moonshot account (`kimi`).
2. `npx skills add amElnagdy/delegate-skills --global --agent claude-code -y --skill kimi-delegate`
3. `lanes set tests kimi`, then `~/orchestra-skills/scripts/smoke-test.sh tests`

**DeepSeek** (docs or code-review, for example), through OpenCode:
1. `npx skills add amElnagdy/delegate-skills --global --agent claude-code -y --skill opencode-delegate`
2. `opencode auth login` → choose DeepSeek → paste your DeepSeek API key.
3. `lanes models opencode | grep -i deepseek` to find the exact model id (`provider/model`).
4. `lanes set docs opencode model=<that id>` (and/or `lanes set code-review opencode model=<id> readonly`).
5. `~/orchestra-skills/scripts/smoke-test.sh docs code-review`

## Older lane names still work

`ui` = `frontend`, `review` = `code-review`, `ui-check` = `ui-review`, `plan-check` =
`architecture-review`, `plan-gate` = `architecture-review-alt`, `done-gate` = `final-audit`.
`lanes resolve` understands both, so an older config keeps working until you switch with
`lanes use default`.

## Undo and test

```bash
lanes undo                                         # previous setup (repeat to go further back)
~/orchestra-skills/scripts/smoke-test.sh backend   # a tiny real task for the jobs you changed
```

Backups are in `~/.config/delegate-skills/backups/`.

## Or just ask Claude

> Move the frontend job to Codex and have Antigravity review the UI.

> Codex hit its limit, move its jobs to Sonnet until it's back.
