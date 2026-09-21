#!/usr/bin/env bash
# Add scoped Antigravity headless permissions for one project folder.
set -euo pipefail

usage() {
  echo "Usage: scripts/agy-allow.sh <project-folder> [--tests \"<command>\"]"
}
[ $# -ge 1 ] || { usage; exit 1; }
DIR="$(cd "$1" && pwd -P)"; shift
CMD=""
if [ "${1:-}" = "--tests" ]; then CMD="${2:?--tests needs a command}"; shift 2; fi
[ $# -eq 0 ] || { echo "Unexpected argument: $1" >&2; usage; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S).$$"
CONFIG_A="$HOME/.gemini/config/config.json"
CONFIG_B="$HOME/.gemini/antigravity-cli/settings.json"
found=0

update_config() {
  local file="$1" schema="$2"
  [ -f "$file" ] || return 0
  found=$((found + 1))
  cp "$file" "$file.bak.$STAMP"
  echo "Updating $file"
  node - "$file" "$DIR" "$CMD" "$schema" <<'JS'
const fs = require('fs');
const [file, dir, cmd, schema] = process.argv.slice(2);
let cfg;
try { cfg = JSON.parse(fs.readFileSync(file, 'utf8')); }
catch (e) { console.error(`Invalid JSON in ${file}: ${e.message}`); process.exit(2); }
let allow;
if (schema === 'global') {
  const us = (cfg.userSettings ??= {});
  const grants = (us.globalPermissionGrants ??= {});
  allow = (grants.allow ??= []);
} else {
  const permissions = (cfg.permissions ??= {});
  allow = (permissions.allow ??= []);
}
if (!Array.isArray(allow)) { console.error(`${file}: permission allow setting is not an array`); process.exit(2); }
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const rules = [`read_file(${dir})`, `write_file(${dir})`];
if (cmd) rules.push(`command(regex:${esc(cmd)}( .*)?)`);
for (const r of rules) {
  if (allow.includes(r)) console.log(`  = ${r} (already there)`);
  else { allow.push(r); console.log(`  + ${r}`); }
}
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + '\n');
JS
}

# Antigravity has used both locations across versions/platforms. Update every existing one;
# headless permission behavior must still be confirmed by smoke-test.sh on the installed version.
update_config "$CONFIG_A" global
update_config "$CONFIG_B" settings

if [ "$found" -eq 0 ]; then
  echo "No Antigravity permission config found." >&2
  echo "Run agy once interactively, then re-run this command." >&2
  echo "Checked: $CONFIG_A and $CONFIG_B" >&2
  exit 1
fi

echo "Done. Added scoped rules for $DIR. Verify them with scripts/smoke-test.sh ui."
