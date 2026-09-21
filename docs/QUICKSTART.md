# Quick start: "I opened Claude Code, what now?"

Read this page first. Everything else is detail.

## Once per machine (5 minutes)

```bash
# 1. Coding tools (by amElnagdy)
npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \
  --skill codex-delegate --skill agy-delegate --skill claude-delegate \
  --skill copilot-delegate --skill delegate-setup

# 2. orchestra-skills
git clone https://github.com/Enadabuzaid/orchestra-skills ~/orchestra-skills
~/orchestra-skills/install.sh

# 3. Log in to each tool once
codex login          # ChatGPT subscription
agy                  # Antigravity (Google): run once, log in, then quit
claude               # Claude Max/Pro subscription (use /login inside if needed)

# 4. If you have an ANTHROPIC_API_KEY for another app, make Claude Code use your subscription:
echo 'claude() { env -u ANTHROPIC_API_KEY command claude "$@"; }' >> ~/.zshrc

# 5. Check
~/orchestra-skills/scripts/doctor.sh       # every line ✓
~/orchestra-skills/scripts/smoke-test.sh   # every lane PASS (or "quota reached" = fine, just wait)
```

## Once per project

```bash
cd ~/Herd/my-project
~/orchestra-skills/scripts/agy-allow.sh . --tests "php artisan test"   # lets Antigravity write here
git status                                                            # commit or stash work in progress first
```

## Every feature

**1. Open Claude Code in the project and choose the thinking model**

```
cd ~/Herd/my-project
claude
/model opus          ← use "fable" for the hardest features
```

`/model` only chooses the **planner**. The checks are always Opus and the coordination is always
Sonnet, whatever you choose here.

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
| 1 | `docs/plans/<date>-<feature>.md` written | Opus (your session) | the plan, with a **Definition of Done** and **Verify** commands |
| 2 | `APPROVE` / `CHANGES REQUIRED` | Opus `plan-reviewer` | the plan is checked against your code. **No code before `APPROVE`** |
| 3 | `relay: completed · codex` / `· agy` / `· claude` | Sonnet `lane-runner` + tools | tasks are built, reviewed and tested; **one commit per task** |
| 4 | a checklist with `file:line` evidence, then `DONE` or `GAPS` | Opus `completion-auditor` | every plan item and every Verify command is checked. Gaps are fixed, then checked again |
| 5 | the final report | Opus | what was built, the commits, the test results, and **one manual check for you** |

**4. Your part**

Do the manual check it gives you (usually "open this page and click this"), look at
`git log --oneline`, and push.

## Change who does what

Ask Claude: *"Use delegate-setup to move the ui lane to codex"*. Or switch to a ready-made map:

```bash
node ~/.claude/skills/delegate-setup/scripts/config.mjs write --scope global ~/orchestra-skills/examples/lanes-codex-frontend.json
~/orchestra-skills/scripts/smoke-test.sh     # confirm
```

Add a `<lane>-check` lane (read-only) to have a second tool review that lane's work before commit.
Details: [GUIDE §9](GUIDE.md#9-changing-lanes-and-models).

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
| `quota` / `usage limit` / 402 / 429 | Nothing is broken. The task moves to `fallback` automatically; the limit resets later |
| `write_file permission auto-denied` (Antigravity) | `~/orchestra-skills/scripts/agy-allow.sh <project>` |
| agent `plan-reviewer`/`lane-runner`/… not found | Restart Claude Code |
| anything else | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
