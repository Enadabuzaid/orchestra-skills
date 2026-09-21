#!/usr/bin/env bash
# Installs orchestra-skills into ~/.claude by symlinking, so `git pull` here updates everything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"
ln -sfn "$ROOT/skills/orchestrate" "$CLAUDE_DIR/skills/orchestrate"
for a in "$ROOT"/agents/*.md; do ln -sfn "$a" "$CLAUDE_DIR/agents/$(basename "$a")"; done

# Append the orchestration rules to the global CLAUDE.md once.
if ! grep -q "^## Orchestration (token budget)" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
  { [ -s "$CLAUDE_DIR/CLAUDE.md" ] && echo; cat "$ROOT/CLAUDE.snippet.md"; } >> "$CLAUDE_DIR/CLAUDE.md"
fi

echo "Installed. Implementer skills come from delegate-skills:"
echo "  npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \\"
echo "    --skill codex-delegate --skill agy-delegate --skill claude-delegate --skill copilot-delegate --skill delegate-setup"
