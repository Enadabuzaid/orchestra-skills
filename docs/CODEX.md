# Using the Codex app as the orchestrator

You can run the whole workflow **from Codex** instead of Claude Code:

| Step | Job lane | Default in the `codex-orchestrator` preset |
|---|---|---|
| Route | – (your Codex session, quick look) | the session model |
| Plan | `planner` / `planner-hard` | Claude Fable / Opus (read-only) |
| Challenge hard plans | `architecture-review` (different family from the planner) | Codex GPT-6 Astra |
| Backend / frontend / tests | `backend`, `frontend`, `tests` | Codex GPT-5.6-Luna / Codex / Codex Luna |
| Reviews | `code-review`, `ui-review`, `security-review` | Haiku / Antigravity / Sonnet |
| Final audit (loops until DONE) | `final-audit` | Claude Opus (read-only) |

Codex uses the `orchestrate-portable` skill. It does the same job as `orchestrate` in Claude Code,
but instead of Claude Code subagents, it calls Claude **through the relay** for the two checks.

## One-time setup

```bash
cd ~/orchestra-skills && git pull && ./install.sh     # links orchestrate-portable into ~/.codex/skills
~/orchestra-skills/scripts/lanes.sh use codex-orchestrator
~/orchestra-skills/scripts/smoke-test.sh planner architecture-review backend frontend final-audit
```

`lanes use codex-orchestrator` sets exactly the table above. Change any row afterwards with
`lanes set …` (see [LANES.md](LANES.md)), for example:

```bash
lanes set planner claude model=opus readonly          # Opus plans instead of Fable
lanes set backend codex model=gpt-5.6-terra           # a bigger Codex model for backend
lanes set frontend agy model=gemini-3.8-flash-high    # frontend on Antigravity instead
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
   - the route (simple / medium / complex / very-complex);
   - `docs/plans/<date>-<feature>.md` from the `planner` lane, with Tasks, Definition of Done and
     Verify;
   - for complex work, the `architecture-review` (a different family) replying `APPROVE` or
     `CHANGES REQUIRED`. No code before `APPROVE`;
   - one task card per task sent to its job lane, then code/ui/security reviews; one commit per task;
   - Codex running every Verify command and handing the output to the `final-audit` lane, which
     replies `DONE` or `GAPS`. Gaps get built, then it checks again;
   - the final report, including a manual check for you.
6. **Do the manual check, then look at `git log` and push.**

## What's different from Claude Code

| | Claude Code (`orchestrate`) | Codex (`orchestrate-portable`) |
|---|---|---|
| Route | `task-router` subagent (Haiku) | your Codex session (quick rubric) |
| Plan | `planner` lane (both) | `planner` lane (both) |
| Challenge | `architecture-review` lane (fallback: Opus `plan-reviewer` subagent) | `architecture-review` lane |
| Coordination | `lane-runner` subagent (Sonnet) | your Codex session itself |
| Final audit | `completion-auditor` subagent (runs the commands itself) | `final-audit` lane: Codex runs the commands, the auditor reads the output |

Both use the same job lanes and the same task cards. Only the coordinator differs: from Codex,
coordination runs on your ChatGPT plan, and Claude is used only by the jobs you map to it.

## Test it

```bash
~/orchestra-skills/scripts/e2e-test.sh --codex
```

Codex (Astra) builds the demo feature unattended with `orchestrate-portable`. Then the script checks
the result itself (17 checks, the same as the Claude Code test).
