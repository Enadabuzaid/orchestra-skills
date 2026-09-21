# Changing who does what (lanes)

A **lane** is a job type mapped to a tool: `backend` → Codex, `ui` → Antigravity, and so on. You
can change any lane at any time with **one command**. Every change is checked before it's saved
and backed up, and `undo` brings the previous setup back.

All commands use `~/orchestra-skills/scripts/lanes.sh`. Tip: add an alias:

```bash
echo "alias lanes='~/orchestra-skills/scripts/lanes.sh'" >> ~/.zshrc && source ~/.zshrc
```

(The examples below use `lanes` for short.)

## See the current setup

```bash
lanes
```
```
LANE             TOOL      MODEL                   EFFORT   MODE        PAID BY
complex          codex     gpt-6-astra             high     writes      ChatGPT
backend          claude    sonnet                  medium   writes      Claude
ui               codex     default                 medium   writes      ChatGPT
ui-check         agy       gemini-3.8-flash-high   default  read-only   Google
small            claude    sonnet                  medium   writes      Claude
fallback         claude    sonnet                  high     writes      Claude
```

## The tools you can use

| Tool name | What it is | Paid by |
|---|---|---|
| `codex` | OpenAI Codex (GPT models) | your ChatGPT subscription |
| `agy` | Google Antigravity (Gemini models) | Google |
| `claude` | Claude Code (`sonnet`, `opus`, `haiku`, `fable`) | your Claude subscription |
| `copilot` | GitHub Copilot (writes need full access, so keep it `readonly`) | GitHub |

See which models a tool has: `lanes models codex`, `lanes models agy`, `lanes models claude`.

## Every common change

| I want to… | Command |
|---|---|
| **Backend → Codex** | `lanes set backend codex effort=medium` |
| **Backend → Claude Sonnet** | `lanes set backend claude model=sonnet effort=medium` |
| **Backend → Antigravity** | `lanes set backend agy model=gemini-3.8-flash-high` |
| **Frontend (ui) → Codex** | `lanes set ui codex effort=medium` |
| **Frontend (ui) → Antigravity** | `lanes set ui agy model=gemini-3.8-flash-high` |
| **Frontend (ui) → Claude Sonnet** | `lanes set ui claude model=sonnet` |
| **Hard tasks → GPT-6 Astra** | `lanes set complex codex model=gpt-6-astra effort=high` |
| **Hard tasks → Claude Opus** | `lanes set complex claude model=opus effort=high` |
| **Fallback → Claude Sonnet** | `lanes set fallback claude model=sonnet effort=high` |
| **Add a checker for frontend** (Antigravity reviews the ui work, read-only) | `lanes set ui-check agy readonly` |
| **Add a checker for backend** (Codex reviews the backend work) | `lanes set backend-check codex readonly` |
| **Remove a checker** | `lanes remove ui-check` |
| **Stronger model for one lane** | `lanes set ui agy model=gemini-3.1-pro-high` |

A lane named **`<lane>-check`** is a *checker*: a second tool reviews that lane's work read-only
before it's committed. The checker's problems go back to the implementer to fix.

## A tool hit its limit (quota)

**One command moves all of that tool's lanes somewhere else:**

```bash
lanes replace codex claude model=sonnet      # Codex out of quota → Claude Sonnet takes over
lanes replace agy codex                      # Antigravity out → Codex takes over
lanes replace claude codex                   # Claude limit reached → Codex takes over
```

**When the quota comes back:**

```bash
lanes undo
```

You don't *have* to do this. When a tool fails because of its quota in the middle of a feature, the
`lane-runner` automatically moves that task to the `fallback` lane. Use `replace` when you know
a tool will be out for a while, so tasks don't waste a failed attempt first.

## Ready-made setups

```bash
lanes presets                 # list them
lanes use default             # backend/complex → Codex, ui → Antigravity, small/fallback → Sonnet
lanes use codex-frontend      # backend → Sonnet, ui → Codex, ui-check → Antigravity
```

To make your own preset, save a lane file as `examples/lanes-<name>.json` in the repo. Then
`lanes use <name>` works.

## Undo anything

```bash
lanes undo                    # restores the previous setup (repeat to go further back)
```

Backups are in `~/.config/delegate-skills/backups/`.

## After any change: test it

```bash
~/orchestra-skills/scripts/smoke-test.sh ui backend    # just the lanes you changed
```

Each lane gets a tiny real coding task. `PASS` means that tool works from that lane. A "quota"
message means the tool is fine but out of quota.

## Or just ask Claude

In Claude Code you can say it in plain words, and Claude runs the command for you:

> Switch the backend lane to Codex and add Antigravity as a checker for the frontend.

> Codex hit its limit, move its lanes to Sonnet until it's back.

## Per-project lanes

A project can have its own lanes: `.delegate/config.json` inside the repo, in the same format.
They replace the global lanes with the same name, for that project only. Claude asks you before
trusting a project's lane file.

## Which setup should I use?

- **Save the most Claude usage:** put the big coding lanes (`backend`, `ui`, `complex`) on `codex`
  or `agy`. Keep `small` and `fallback` on Sonnet.
- **Best quality on hard work:** `complex` → `codex model=gpt-6-astra` or `claude model=opus`.
- **Two opinions on the frontend:** `ui` → one tool, `ui-check` → another.
- **Every lane on `claude`** works, but then all coding uses your Claude plan. That's fine as a
  temporary fallback, but it's not the token-saving setup.
