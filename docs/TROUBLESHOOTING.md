# Troubleshooting

Start with `scripts/doctor.sh`. It checks installs, links, lanes and logins, and changes nothing.
Then run `scripts/smoke-test.sh <lane>` for the lane in trouble. Every failure line points to a log
file; each lane's `result.json` is in `<work dir>/<lane>.run/`.

| Symptom | Cause | Fix |
|---|---|---|
| `ui` lane: *"a tool required the write_file permission that headless mode cannot prompt for, so it was auto-denied"* | Headless Antigravity cannot ask you for permission | `scripts/agy-allow.sh <your project folder>`. Add `--tests "<test cmd>"` if it should run tests too |
| Antigravity writes but can't run your tests | No command rule for that command | `scripts/agy-allow.sh <folder> --tests "php artisan test"` (use your own test command) |
| Copilot lane: *"Permission denied and could not request permission"* | Headless Copilot writes only with `--allow-all-tools` (full access) | Keep Copilot read-only (default `copilot-review` lane), or accept full access for that one run |
| Copilot lane: *"copilot version preflight timed out after 10000ms"* | Copilot's start-up check has a hard 10s limit that it can miss when the machine is busy | Retry when fewer lanes are running. `smoke-test.sh` already runs Copilot last |
| Any lane: *quota or rate limit reached* / HTTP 402 or 429 | That provider's monthly or hourly quota is used up | Wait for the reset, or send the task to `fallback`. The setup is fine |
| `status: codex_unavailable` / `agy_unavailable` / … | CLI not installed or not on `PATH` | Install it, then run `doctor.sh` |
| doctor shows *NOT logged in* | CLI not logged in | `codex login`, run `agy` once, `gh auth login` |
| `plan-reviewer` / `diff-reviewer` / `completion-auditor` not found | Claude Code started before the agents were installed | Restart Claude Code; check `ls ~/.claude/agents` |
| `orchestrate` skill not offered | Link missing | Run `~/orchestra-skills/install.sh` again |
| A lane uses the wrong model | The lane config differs from what you expect | `doctor.sh` prints the lanes; fix them with section 9 of the [guide](GUIDE.md#9-changing-lanes-and-models) |
| `status: aborted` — *"the relay was killed by SIGTERM"* | Claude ended its turn while a run was still going. In headless mode (`claude -p`) that ends the process and kills the run | Fixed in the skill (v0.2.0): Claude now blocks until `result.json` exists. For your own scripts, keep the session alive until the relays finish |
| *"claude.ai connectors are disabled because ANTHROPIC_API_KEY … is set"* | An API key in your environment takes precedence over your claude.ai login, so usage is billed to the API key | `unset ANTHROPIC_API_KEY` in the shell if you want your subscription to be used |
| An implementer committed | Should never happen (relays don't commit and briefs forbid it) | `git reset --soft HEAD~1`, review the change, and report it upstream to delegate-skills |
| `readOnlyViolation` in `result.json` | A read-only run changed files | Inspect with `git status`, discard with `git checkout -- <files>`, and report it upstream |
| `orchestra roles` shows `NONE AVAILABLE` for every role, or "`<tool> CLI not installed`" for a CLI that is on your PATH | CLI discovery failed or timed out (it probes every CLI) | Fixed in v0.5.1: a failed probe is never cached; the last good result or a PATH check is used. Run `orchestra roles --refresh`; `doctor.sh` prints the reason per model |
| `orchestra resolve review` skips Kimi with "relay has no --read-only" | Kimi's relay can't enforce read-only, and reviews must not write | Expected. Kimi builds (backend, tests, …); reviews go to the next model in the chain |
| `orchestra check` says "writes, but model copilot can only run read-only" | You put Copilot in a builder chain | Keep Copilot in read-only roles (`review`, `ui-review`, `security-review`), or accept `--allow-all-tools` by running it by hand |
| A builder loops for hundreds of thousands of tokens on a small task | A too-small model as builder (recorded: Haiku, 650k tokens on a README) | Haiku is out of every builder chain since v0.5.1. If you added a small model, move it behind Sonnet, or make it read-only |
| `antigravity … auto-denied the command permission` | Headless Antigravity may run only allowed commands | `scripts/agy-allow.sh <project> --tests "<your test command>"`; the task falls back to the next model meanwhile |

## Reading a relay result

```bash
node -e 'const r=require(process.argv[1]); console.log(r.status, r.exitCode, r.error ?? ""); console.log(r.finalMessage)' <out-dir>/result.json
```

`status` is one of `completed`, `failed`, `timeout`, `aborted`, or `<cli>_unavailable`.
`touchedFiles` lists what changed. For Copilot, the reason is in `events.jsonl` (search for
`session.error`).
