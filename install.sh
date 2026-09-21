#!/usr/bin/env bash
# Installs orchestra-skills into Claude Code and Codex by symlinking this checkout.
# Safe to re-run: existing orchestra links are reused; conflicting files are backed up first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
STAMP="$(date +%Y%m%d%H%M%S).$$"

need_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js 18+ is required (node not found)." >&2
    exit 1
  fi
  local major
  major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
  if [ "$major" -lt 18 ]; then
    echo "Node.js 18+ is required (found $(node --version 2>/dev/null || echo unknown))." >&2
    exit 1
  fi
}

backup_target() {
  local target="$1" backup
  backup="${target}.orchestra-backup.${STAMP}"
  mv "$target" "$backup"
  echo "Backed up existing $target -> $backup"
}

safe_link() {
  local source="$1" target="$2" current=""
  if [ -L "$target" ]; then
    current="$(readlink "$target" 2>/dev/null || true)"
    if [ "$current" = "$source" ]; then
      return
    fi
    backup_target "$target"
  elif [ -e "$target" ]; then
    backup_target "$target"
  fi
  ln -s "$source" "$target"
}

update_marked_file() {
  local file="$1" snippet="$2" start="$3" end="$4" tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp "${TMPDIR:-/tmp}/orchestra-install.XXXXXX")"
  node - "$file" "$snippet" "$start" "$end" "$tmp" <<'JS'
const fs = require("fs");
const [file, snippetFile, start, end, out] = process.argv.slice(2);
let md = fs.readFileSync(file, "utf8");
const block = `${start}\n${fs.readFileSync(snippetFile, "utf8").trim()}\n${end}`;

// Older Claude installs appended this section without markers. Remove only that legacy block.
if (snippetFile.endsWith("CLAUDE.snippet.md")) {
  md = md.replace(/## Orchestration \(token budget\)[\s\S]*?(?=\n## |\n<!-- |$)/, "");
}
md = md.trimEnd();

const escapedStart = start.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const escapedEnd = end.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const re = new RegExp(`${escapedStart}[\\s\\S]*?${escapedEnd}`);
const next = (re.test(md) ? md.replace(re, block) : (md.trimEnd() ? `${md.trimEnd()}\n\n${block}` : block)) + "\n";
fs.writeFileSync(out, next);
JS

  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return
  fi

  if [ -s "$file" ]; then
    cp "$file" "${file}.orchestra-backup.${STAMP}"
    echo "Backed up existing $file -> ${file}.orchestra-backup.${STAMP}"
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

need_node

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"
safe_link "$ROOT/skills/orchestrate" "$CLAUDE_DIR/skills/orchestrate"
for a in "$ROOT"/agents/*.md; do
  safe_link "$a" "$CLAUDE_DIR/agents/$(basename "$a")"
done

START="<!-- orchestra-skills:start -->"
END="<!-- orchestra-skills:end -->"
update_marked_file "$CLAUDE_DIR/CLAUDE.md" "$ROOT/CLAUDE.snippet.md" "$START" "$END"

# Default lane map, only if you don't have one yet (never overwrites).
LANES="${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json"
if [ ! -f "$LANES" ]; then
  mkdir -p "$(dirname "$LANES")"
  cp "$ROOT/examples/lanes.json" "$LANES"
  echo "Wrote default lanes to $LANES"
fi

# Codex app / CLI: install only when the Codex home already exists.
if [ -d "$CODEX_DIR" ]; then
  mkdir -p "$CODEX_DIR/skills"
  safe_link "$ROOT/skills/orchestrate-portable" "$CODEX_DIR/skills/orchestrate-portable"
  update_marked_file "$CODEX_DIR/AGENTS.md" "$ROOT/CODEX.snippet.md" "$START" "$END"
  echo "Codex: linked orchestrate-portable into $CODEX_DIR/skills and updated $CODEX_DIR/AGENTS.md"
fi

echo "Installed. Implementer skills come from delegate-skills:"
echo "  npx skills add amElnagdy/delegate-skills --global --agent claude-code -y \\"
echo "    --skill codex-delegate --skill agy-delegate --skill claude-delegate --skill copilot-delegate --skill delegate-setup"
