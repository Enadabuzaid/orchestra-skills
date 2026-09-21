#!/usr/bin/env bash
# Change who does what: one command per change. Every change is validated and backed up first.
#
#   lanes.sh                                   show the current lanes
#   lanes.sh set <lane> <tool> [model=M] [effort=E] [readonly]
#                                              set (or create) a lane
#   lanes.sh remove <lane>                     delete a lane
#   lanes.sh replace <tool> <new-tool> [model=M] [effort=E]
#                                              move every lane of one tool to another
#                                              (e.g. Codex hit its limit: replace codex claude model=sonnet)
#   lanes.sh use <preset>                      switch to a ready-made map (see: lanes.sh presets)
#   lanes.sh presets                           list ready-made maps
#   lanes.sh models <tool>                     list the models a tool offers
#   lanes.sh undo                              restore the previous lanes
#
# Tools: codex, agy (Antigravity), claude, copilot (and any other delegate-skills implementer).
# Examples:
#   lanes.sh set backend codex effort=medium
#   lanes.sh set backend claude model=sonnet effort=medium
#   lanes.sh set ui agy model=gemini-3.8-flash-high
#   lanes.sh set ui-check agy readonly
#   lanes.sh remove ui-check
#   lanes.sh replace codex claude model=sonnet    # Codex out of quota → Sonnet takes its lanes
#   lanes.sh undo                                # quota back → restore
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="${SKILLS_DIR:-$HOME/.claude/skills}/delegate-setup/scripts"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json"
BACKUPS="$(dirname "$CONFIG")/backups"

show() {
  [ -f "$CONFIG" ] || { echo "No lanes yet. Run: lanes.sh use default"; return; }
  node -e '
    const c = require(process.argv[1]);
    const pay = { codex: "ChatGPT", agy: "Google", claude: "Claude", copilot: "GitHub" };
    console.log("LANE             TOOL      MODEL                   EFFORT   MODE        PAID BY");
    for (const [n, l] of Object.entries(c.lanes))
      console.log(n.padEnd(17) + l.implementer.padEnd(10) + String(l.model || "default").padEnd(24) +
        String(l.effort || l.variant || "default").padEnd(9) + (l.readOnly ? "read-only" : "writes").padEnd(12) + (pay[l.implementer] || "?"));
  ' "$CONFIG"
}

save() {  # $1 = candidate file; validate, back up the current config, write
  local err; err="$(node "$SETUP/config.mjs" validate "$1" 2>&1 >/dev/null)" || { echo "$err" | head -3; echo "Not saved."; exit 1; }
  if [ -f "$CONFIG" ]; then mkdir -p "$BACKUPS"; cp "$CONFIG" "$BACKUPS/config.$(date +%Y%m%d-%H%M%S).json"; fi
  node "$SETUP/config.mjs" write --scope global "$1" >/dev/null
  echo "Saved. Current lanes:"; echo; show
  echo; echo "Test it:  $ROOT/scripts/smoke-test.sh <lane>"
}

cmd="${1:-show}"; shift || true
case "$cmd" in
  show|"") show ;;

  set)
    lane="${1:?usage: lanes.sh set <lane> <tool> [model=M] [effort=E] [readonly]}"; tool="${2:?which tool? codex, agy, claude, copilot}"; shift 2
    tmp="$(mktemp)"
    node -e '
      const fs = require("fs");
      const [cfgPath, out, lane, tool, ...opts] = process.argv.slice(1);
      const c = fs.existsSync(cfgPath) ? JSON.parse(fs.readFileSync(cfgPath, "utf8")) : { version: "delegate-fleet.v1", lanes: {} };
      const l = { implementer: tool };
      for (const o of opts) {
        if (o === "readonly" || o === "read-only") l.readOnly = true;
        else { const i = o.indexOf("="); if (i < 1) { console.error(`bad option: ${o} (use key=value or readonly)`); process.exit(2); }
               const k = o.slice(0, i), v = o.slice(i + 1); l[k === "readonly" ? "readOnly" : k] = v === "true" ? true : v; }
      }
      c.lanes[lane] = l;
      fs.writeFileSync(out, JSON.stringify(c, null, 2) + "\n");
    ' "$CONFIG" "$tmp" "$lane" "$tool" "$@"
    save "$tmp"; rm -f "$tmp" ;;

  remove|rm)
    lane="${1:?usage: lanes.sh remove <lane>}"; tmp="$(mktemp)"
    node -e '
      const fs = require("fs"); const [p, out, lane] = process.argv.slice(1);
      const c = JSON.parse(fs.readFileSync(p, "utf8"));
      if (!c.lanes[lane]) { console.error(`no lane called ${lane}`); process.exit(2); }
      delete c.lanes[lane]; fs.writeFileSync(out, JSON.stringify(c, null, 2) + "\n");
    ' "$CONFIG" "$tmp" "$lane"
    save "$tmp"; rm -f "$tmp" ;;

  replace|swap)
    from="${1:?usage: lanes.sh replace <tool> <new-tool> [model=M] [effort=E]}"; to="${2:?which new tool?}"; shift 2
    tmp="$(mktemp)"
    node -e '
      const fs = require("fs");
      const [p, out, from, to, ...opts] = process.argv.slice(1);
      const c = JSON.parse(fs.readFileSync(p, "utf8")); let n = 0;
      for (const [name, l] of Object.entries(c.lanes)) {
        if (l.implementer !== from) continue;
        const nl = { implementer: to };
        for (const o of opts) { const i = o.indexOf("="); if (i > 0) nl[o.slice(0, i)] = o.slice(i + 1); }
        if (l.readOnly) nl.readOnly = true;            // keep read-only lanes read-only
        c.lanes[name] = nl; n++; console.log(`  ${name}: ${from} → ${to}`);
      }
      if (!n) { console.error(`no lane uses ${from}`); process.exit(2); }
      fs.writeFileSync(out, JSON.stringify(c, null, 2) + "\n");
    ' "$CONFIG" "$tmp" "$from" "$to" "$@"
    save "$tmp"; rm -f "$tmp" ;;

  presets)
    for f in "$ROOT"/examples/lanes*.json; do
      n="$(basename "$f" .json)"; n="${n#lanes-}"; [ "$n" = "lanes" ] && n="default"; echo "  $n"
    done ;;

  use)
    p="${1:?usage: lanes.sh use <preset>  (see: lanes.sh presets)}"
    f="$ROOT/examples/lanes-$p.json"; [ "$p" = "default" ] && f="$ROOT/examples/lanes.json"
    [ -f "$f" ] || { echo "No preset '$p'. Presets:"; "$0" presets; exit 1; }
    tmp="$(mktemp)"; cp "$f" "$tmp"; save "$tmp"; rm -f "$tmp" ;;

  models)
    tool="${1:?usage: lanes.sh models <tool>}"
    node "$SETUP/discover.mjs" 2>/dev/null | node -e '
      const d = JSON.parse(require("fs").readFileSync(0)); const t = process.argv[1];
      const x = d.discovered.find((e) => e.key === t);
      if (!x) { console.log(`${t}: not installed`); process.exit(1); }
      const vals = (x.models && x.models.values) || [];
      console.log(vals.length ? vals.filter((v) => !v.startsWith("[")).map((v) => "  " + v.split("\t")[0]).join("\n")
                              : `  ${t} does not list models (status: ${x.models && x.models.status}); leave model unset to use its default`);
    ' "$tool" ;;

  undo)
    last="$(ls -t "$BACKUPS"/config.*.json 2>/dev/null | head -1 || true)"
    [ -n "$last" ] || { echo "Nothing to undo."; exit 1; }
    cp "$last" "$CONFIG" && rm -f "$last"; echo "Restored $(basename "$last")."; echo; show ;;

  -h|--help|help) sed -n '2,25p' "$0" ;;
  *) echo "Unknown command: $cmd"; sed -n '2,25p' "$0"; exit 1 ;;
esac
