#!/usr/bin/env bash
# Let Antigravity (agy) write files in a folder during headless delegated runs.
#
#   scripts/agy-allow.sh ~/Code/my-project            # allow writes in that folder (recursive)
#   scripts/agy-allow.sh ~/Code/my-project --tests "php artisan test"   # also allow a test command
#
# Why: headless `agy --print` cannot ask you for permission, so writes are auto-denied unless
# a rule allows them. This adds a *scoped* rule (one folder, one command pattern) instead of
# --dangerously-skip-permissions, which would approve every tool everywhere.
#
# Rules go to ~/.gemini/config/config.json (userSettings.globalPermissionGrants.allow), the file
# agy 1.2.x reads on macOS. A timestamped backup is written next to it first.
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 1; }
DIR="$(cd "$1" && pwd -P)"; shift
CMD=""
if [ "${1:-}" = "--tests" ]; then CMD="${2:?--tests needs a command}"; fi

CONFIG="$HOME/.gemini/config/config.json"
[ -f "$CONFIG" ] || { echo "No $CONFIG. Run agy once interactively first."; exit 1; }
cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d%H%M%S)"

node -e '
  const fs = require("fs");
  const [file, dir, cmd] = process.argv.slice(1);
  const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
  const us = (cfg.userSettings ??= {});
  const grants = (us.globalPermissionGrants ??= {});
  const allow = (grants.allow ??= []);
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const rules = [`read_file(${dir})`, `write_file(${dir})`];
  if (cmd) rules.push(`command(regex:${esc(cmd)}( .*)?)`);
  for (const r of rules) {
    if (allow.includes(r)) console.log(`  = ${r} (already there)`);
    else { allow.push(r); console.log(`  + ${r}`); }
  }
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
' "$CONFIG" "$DIR" "$CMD"
echo "Done. Antigravity can now write inside $DIR during delegated runs."
