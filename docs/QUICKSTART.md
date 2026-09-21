# Quick start: "I opened Claude Code, what now?"

Read this page first. Everything else is detail.

## Once per machine (5 minutes)

```bash
# 1. Coding tools (by amElnagdy): install the relays for the CLIs you have; the policy skips the rest
npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \
  --skill delegate-setup --skill claude-delegate --skill codex-delegate --skill agy-delegate \
  --skill copilot-delegate --skill kimi-delegate --skill opencode-delegate

# 2. orchestra-skills (any folder; the installer links ~/orchestra-skills and ~/.local/bin/orchestra)
git clone https://github.com/Enadabuzaid/orchestra-skills ~/orchestra-skills
~/orchestra-skills/install.sh

# 3. Log in to each tool once (only the ones you have)
claude               # Claude Max/Pro subscription (use /login inside if needed)
codex login          # ChatGPT subscription: Codex, GPT-5.6 Luna, GPT-6 Astra
agy                  # Antigravity (Google): run once, log in, then quit
copilot login        # GitHub Copilot (read-only reviews)
kimi                 # Kimi Code (Moonshot)
opencode auth login  # DeepSeek (paste your key); the free OpenCode tier needs no login

# 4. If you have an ANTHROPIC_API_KEY for another app, make Claude Code use your subscription:
echo 'claude() { env -u ANTHROPIC_API_KEY command claude "$@"; }' >> ~/.zshrc

# 5. Check
~/orchestra-skills/scripts/doctor.sh                       # every line ✓, and the model each role uses now
~/orchestra-skills/scripts/smoke-test.sh role:backend role:review role:frontend   # a real task through those models
```

## Once per project (works in any project)

Nothing is installed inside the project. The plan lands in the project's `docs/plans/`, commits are
per task, and run logs stay outside the repo.

```bash
cd ~/Herd/my-project
~/orchestra-skills/scripts/doctor.sh .                                # git? clean tree? test command? Antigravity allowed?
~/orchestra-skills/scripts/agy-allow.sh . --tests "php artisan test"  # only if the doctor asks: lets Antigravity write and test here
git status                                                            # commit or stash work in progress first
```

## Every feature

**1. Open Claude Code in the project**

```
cd ~/Herd/my-project
claude
/model sonnet        ← the session only routes and coordinates
```

The thinking is done by roles, not by your session: the planner is Fable (Opus when the router says
Hard), the second opinion Astra, the final audit Opus, whatever `/model` says. Builders and
reviewers are the cheapest available model in their chain (`orchestra roles`).

**2. Ask**

> Use orchestrate to <what you want>. Done means: <what a user can do / see>. Don't touch <what to leave alone>.

Examples:

> Use orchestrate to make sure patient login and registration work end to end and fix whatever fails.

> Use orchestrate to let patients cancel a booking up to 24h before the visit. Done means: a cancel
> button on the booking page, status becomes "cancelled", the provider gets an email. Don't touch payments.

For a **small change** (one file, a typo, a quick fix), just ask normally without "orchestrate".

**3. Watch these 5 things happen**

| # | You'll see | Model | It means |
|---|---|---|---|
| 1 | `ROUTE: tiny / small / feature / complex` | Haiku `task-router` | how much process this request gets. Tiny = one card, no plan, no audit |
| 2 | `docs/plans/<date>-<feature>.md` written (feature, complex) | Fable `planner` (Opus if Hard) | the plan, with a **Definition of Done** and **Verify** commands. Complex work touching architecture/security/payments/migrations also gets Astra's `APPROVE` / `CHANGES REQUIRED` |
| 3 | `relay: completed · codex` / `· agy` / `· opencode` / `· claude` | Sonnet `lane-runner` + the models the policy picks | tasks are built, gated, reviewed by a different model and tested; **one commit per task** |
| 4 | a checklist with `file:line` evidence, then `DONE` or `GAPS` | Opus `completion-auditor` | every plan item and every Verify command is checked. Gaps are fixed, then re-verified |
| 5 | the final report with `orchestra metrics` | your session | route, expensive calls used / budget, fallbacks, tasks → model → commit, test results, and **one manual check for you** |

**4. Your part**

Do the manual check it gives you (usually "open this page and click this"), look at
`git log --oneline`, and push.

## Change who does what

Since v0.5: `orchestra roles` shows every role and the model it uses now; `orchestra set backend codex kimi sonnet`
changes a chain; `orchestra exhausted codex --until 21:34` skips a tool that hit its quota. Details: **[POLICY.md](POLICY.md)**.
The older lane commands below still work for single relays.

```bash
~/orchestra-skills/scripts/lanes.sh                                   # show
~/orchestra-skills/scripts/lanes.sh set backend codex                 # backend → Codex
~/orchestra-skills/scripts/lanes.sh set ui agy                        # frontend → Antigravity
~/orchestra-skills/scripts/lanes.sh replace codex claude model=sonnet # Codex hit its limit
~/orchestra-skills/scripts/lanes.sh undo                              # back to the previous setup
```

Every change with examples: **[LANES.md](LANES.md)**.

## Where did the tokens go?

```bash
~/orchestra-skills/scripts/token-report.sh <project-folder-name>
```

In Claude Code: `/cost` for this session, `/usage` for your plan limits.

Rows marked **ChatGPT** or **Google** used zero Claude tokens. Real numbers from a run are in
[EXAMPLE.md](EXAMPLE.md#what-actually-happened-2026-09-21).

## If something goes wrong

| You see | Do |
|---|---|
| `quota` / `usage limit` / 402 / 429 | Nothing is broken. The tool is marked exhausted (`orchestra exhausted <tool> --until HH:MM`) and every role uses its next model until then |
| `NONE AVAILABLE` for a role in the doctor | Every model in that chain is unavailable; the doctor prints why for each. Log in to a tool, or `orchestra set <role> <model> …` |
| `write_file permission auto-denied` (Antigravity) | `~/orchestra-skills/scripts/agy-allow.sh <project>` |
| agent `plan-reviewer`/`lane-runner`/… not found | Restart Claude Code |
| anything else | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
