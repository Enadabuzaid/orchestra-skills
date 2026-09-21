# Using the Codex app as the orchestrator

You can run the whole workflow **from Codex** instead of Claude Code:

| Step | Role | Default policy (`orchestra roles`) |
|---|---|---|
| Route | – (your Codex session, the rubric in `agents/task-router.md`) | the session model |
| Plan | `planner` / `planner-hard` | Claude Fable → Astra → Opus / Opus → Fable → Astra (read-only) |
| Second opinion on complex plans | `architecture` (a different family from the planner) | Codex GPT-6 Astra → Opus |
| Backend / frontend / tests / docs | `backend`, `frontend`, `tests`, `docs` | the cheapest available: Codex, Antigravity, Kimi, DeepSeek, Luna, OpenCode free, then Sonnet |
| Reviews (read-only, never the builder's model) | `review`, `ui-review`, `security-review` | DeepSeek/Luna/OpenCode free/Copilot/Haiku/Sonnet · Codex/Luna/Copilot/Sonnet · Astra/Copilot/Sonnet |
| Final audit (loops until DONE) | `final-audit` | Claude Opus (read-only) |

Codex uses the `orchestrate-portable` skill. It does the same job as `orchestrate` in Claude Code,
but instead of Claude Code subagents, it calls the roles **through the relays**, including Claude
for the plan and the final audit.

## One-time setup

```bash
cd ~/orchestra-skills && git pull && ./install.sh     # links orchestrate-portable into ~/.codex/skills
~/orchestra-skills/scripts/doctor.sh                  # every role has an available model?
~/orchestra-skills/scripts/smoke-test.sh role:planner role:architecture role:backend role:frontend role:final-audit
```

The same policy file serves Claude Code and Codex. Change a chain with `orchestra set` (see
[POLICY.md](POLICY.md)), for example:

```bash
orchestra set planner opus fable astra --read-only    # Opus plans first
orchestra model terra tool=codex model=gpt-5.6-terra effort=high && orchestra set backend terra codex luna sonnet
orchestra set frontend antigravity codex sonnet       # frontend on Antigravity first
orchestra check                                       # the policy is still valid
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
   - the route (tiny / small / feature / complex);
   - `docs/plans/<date>-<feature>.md` from the `planner` role, with Tasks, Definition of Done and
     Verify;
   - for complex work touching architecture, security, payments or migrations, the `architecture`
     role (a different family) replying `APPROVE` or `CHANGES REQUIRED`. No code before `APPROVE`;
   - one task card per task sent to its role's model, then review / ui-review / security-review by a
     different model; one commit per task;
   - Codex running every Verify command and handing the output to the `final-audit` role, which
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
