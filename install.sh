#!/usr/bin/env bash
# Installs orchestra-skills into ~/.claude by symlinking, so `git pull` here updates everything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"
ln -sfn "$ROOT/skills/orchestrate" "$CLAUDE_DIR/skills/orchestrate"
for a in "$ROOT"/agents/*.md; do ln -sfn "$a" "$CLAUDE_DIR/agents/$(basename "$a")"; done

# Put the orchestration rules in the global CLAUDE.md between markers (re-running replaces them).
START="<!-- orchestra-skills:start -->"; END="<!-- orchestra-skills:end -->"
touch "$CLAUDE_DIR/CLAUDE.md"
node -e '
  const fs = require("fs");
  const [file, snippetFile, start, end] = process.argv.slice(1);
  let md = fs.readFileSync(file, "utf8");
  const block = `${start}\n${fs.readFileSync(snippetFile, "utf8").trim()}\n${end}`;
  // Older installs appended the snippet without markers; drop that copy.
  md = md.replace(/## Orchestration \(token budget\)[\s\S]*?(?=\n## |\n<!-- |$)/, "").trimEnd();
  const re = new RegExp(`${start}[\\s\\S]*?${end}`);
  md = re.test(md) ? md.replace(re, block) : (md ? md + "\n\n" : "") + block;
  fs.writeFileSync(file, md + "\n");
' "$CLAUDE_DIR/CLAUDE.md" "$ROOT/CLAUDE.snippet.md" "$START" "$END"

# Default lane map, only if you don't have one yet (never overwrites).
LANES="${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json"
if [ ! -f "$LANES" ]; then
  mkdir -p "$(dirname "$LANES")" && cp "$ROOT/examples/lanes.json" "$LANES"
  echo "Wrote default lanes to $LANES"
fi

echo "Installed. Implementer skills come from delegate-skills:"
echo "  npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \\"
echo "    --skill codex-delegate --skill agy-delegate --skill claude-delegate --skill copilot-delegate --skill delegate-setup"
