# orchestra-skills

Use big models to think and cheap models to type, for Claude Code.

| Stage | Model |
|---|---|
| Plan | Fable / Opus |
| **Plan gate** (`plan-reviewer`) | Opus, loops until `APPROVE` |
| Implement | [delegate-skills](https://github.com/amElnagdy/delegate-skills) lanes: Codex, Antigravity (Gemini), Claude Sonnet, Copilot |
| Per-task review (`diff-reviewer`) | Sonnet |
| Commit | Orchestrator only |
| Final audit | Opus, once per feature |

This repo contains only the orchestration layer. Sending work to the other tools is handled by
`delegate-skills`, which you install separately.

## Install

```bash
# 1. Implementers
npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \
  --skill codex-delegate --skill agy-delegate --skill claude-delegate --skill copilot-delegate --skill delegate-setup

# 2. This repo
git clone <this-repo> ~/orchestra-skills && ~/orchestra-skills/install.sh

# 3. Lanes (in Claude Code)
#    "Use delegate-setup to configure lanes backend, ui, small, fallback"
#    or copy examples/lanes.json to ~/.config/delegate-skills/config.json
```

## Use

> Use orchestrate to build <feature>.

## Contents

- `skills/orchestrate/`: the 7-stage workflow and the brief template
- `agents/plan-reviewer.md`: Opus plan gate
- `agents/diff-reviewer.md`: Sonnet per-task reviewer
- `CLAUDE.snippet.md`: rules appended to `~/.claude/CLAUDE.md`
- `examples/lanes.json`: the default lane map

MIT licensed.
