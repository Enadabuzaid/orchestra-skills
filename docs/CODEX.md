# Using the Codex app as the orchestrator

You can run the whole workflow **from Codex** instead of Claude Code:

| Step | Who | How it's chosen |
|---|---|---|
| Plan | **GPT-6 Astra**: your Codex session | `/model gpt-6-astra` in Codex |
| Check the plan | **Claude Fable**, read-only | the `plan-gate` lane |
| Backend | **Codex GPT-5.6-Luna** (small, cheap) | the `backend` lane |
| Frontend | **Codex** | the `ui` lane |
| Check the frontend | **Antigravity**, read-only | the `ui-check` lane |
| Small fixes / fallback | **Claude Sonnet** | the `small` / `fallback` lanes |
| Final done check (loops until DONE) | **Claude Opus**, read-only | the `done-gate` lane |

Codex uses the `orchestrate-portable` skill. It does the same job as `orchestrate` in Claude Code,
but instead of Claude Code subagents, it calls Claude **through the relay** for the two checks.

## One-time setup

```bash
cd ~/orchestra-skills && git pull && ./install.sh     # links orchestrate-portable into ~/.codex/skills
~/orchestra-skills/scripts/lanes.sh use codex-orchestrator
~/orchestra-skills/scripts/smoke-test.sh plan-gate done-gate backend ui
```

`lanes use codex-orchestrator` sets exactly the table above. Change any row afterwards with
`lanes set …` (see [LANES.md](LANES.md)), for example:

```bash
lanes set plan-gate claude model=opus readonly        # Opus checks the plan instead of Fable
lanes set backend codex model=gpt-5.6-terra           # a bigger Codex model for backend
lanes set ui agy model=gemini-3.8-flash-high          # frontend on Antigravity instead
```

## Every feature, step by step

1. **Open the Codex app in your project folder** (for example `~/Herd/home-visit`).
2. **Pick Astra as the planner:** `/model gpt-6-astra`.
3. **Give it full access for this session.** The workflow starts other CLIs (Claude, Codex,
   Antigravity) that need the network and write their own session files. Codex's default sandbox
   blocks that. In the app, choose **Full access**, or approve each `node …/relay.mjs` command when
   Codex asks. On the CLI, use `codex -s danger-full-access`.
4. **Ask:**
   > Use orchestrate-portable to let patients cancel a booking up to 24h before the visit. Done means:
   > cancel button on the booking page, status becomes "cancelled", provider gets an email.
5. **Watch for these, in order:**
   - `docs/plans/<date>-<feature>.md`, written by Astra, with Tasks, Definition of Done and Verify;
   - **Claude Fable** replying `APPROVE` or `CHANGES REQUIRED` (the plan-gate). No code before
     `APPROVE`;
   - tasks sent to their lanes: `relay: completed · codex` (backend on Luna, ui on Codex), then the
     `ui-check` review by Antigravity; one commit per task;
   - Codex running every Verify command and handing the output to **Claude Opus** (the done-gate),
     which replies `DONE` or `GAPS`. Gaps get built, then Opus checks again;
   - the final report, including a manual check for you.
6. **Do the manual check, then look at `git log` and push.**

## What's different from Claude Code

| | Claude Code (`orchestrate`) | Codex (`orchestrate-portable`) |
|---|---|---|
| Planner | Opus/Fable (`/model`) | Astra (`/model gpt-6-astra`) |
| Plan check | `plan-reviewer` subagent (Opus) | `plan-gate` lane (Claude, read-only) |
| Coordination | `lane-runner` subagent (Sonnet) | your Codex session itself |
| Done check | `completion-auditor` subagent (runs the commands itself) | `done-gate` lane: Codex runs the commands, Claude reads the output |
| Paid by | Claude plan for the thinking | **ChatGPT plan for the thinking and coordination**, Claude only for the 2 checks |

In Codex mode your **Claude plan is used only for the two short checks**, plus the Sonnet
`small`/`fallback` lanes if they're used. Planning, coordination and most coding run on ChatGPT.

## Test it

```bash
~/orchestra-skills/scripts/e2e-test.sh --codex
```

Codex (Astra) builds the demo feature unattended with `orchestrate-portable`. Then the script checks
the result itself (17 checks, the same as the Claude Code test).
