#!/usr/bin/env bash
# Checks that everything orchestrate needs is installed and wired up. Changes nothing.
set -uo pipefail
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json"
ok=0; bad=0
pass() { echo "  ✓ $1"; ok=$((ok + 1)); }
fail() { echo "  ✗ $1"; bad=$((bad + 1)); }

echo "Base tools"
command -v node >/dev/null && pass "node $(node --version)" || fail "node not found (Node 18+ required)"
command -v git  >/dev/null && pass "git" || fail "git not found"
command -v claude >/dev/null && pass "claude" || fail "claude not found"

echo "orchestra-skills"
[ -f "$CLAUDE_DIR/skills/orchestrate/SKILL.md" ] && pass "orchestrate skill" || fail "orchestrate skill missing: run ./install.sh"
for a in plan-reviewer diff-reviewer completion-auditor lane-runner; do
  [ -f "$CLAUDE_DIR/agents/$a.md" ] && pass "$a agent" || fail "$a agent missing: run ./install.sh"
done
grep -q "^## Orchestration (token budget)" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null && pass "CLAUDE.md rules" || fail "CLAUDE.md rules missing: run ./install.sh"

echo "delegate-skills"
for s in delegate-setup codex-delegate agy-delegate claude-delegate copilot-delegate; do
  [ -f "$CLAUDE_DIR/skills/$s/SKILL.md" ] && pass "$s" || fail "$s missing (see README install step 1)"
done

echo "Lanes ($CONFIG)"
if [ -f "$CONFIG" ]; then
  node -e '
    const c = require(process.argv[1]);
    for (const [n, l] of Object.entries(c.lanes)) {
      const dials = Object.entries(l).filter(([k]) => k !== "implementer").map(([k, v]) => `${k}=${v}`).join(" ");
      console.log(`    ${n.padEnd(11)} → ${l.implementer.padEnd(8)} ${dials}`);
    }' "$CONFIG"
  pass "lane config present"
else
  fail "no lane config: copy examples/lanes.json there or run delegate-setup"
fi

echo "Implementer CLIs (installed / logged in)"
DISCOVER="$CLAUDE_DIR/skills/delegate-setup/scripts/discover.mjs"
if [ -f "$DISCOVER" ]; then
  node "$DISCOVER" 2>/dev/null | node -e '
    const d = JSON.parse(require("fs").readFileSync(0));
    const want = ["codex", "agy", "claude", "copilot"];
    for (const k of want) {
      const x = d.discovered.find(e => e.key === k);
      if (!x) { console.log(`  ✗ ${k}: not installed`); continue; }
      const auth = x.authenticated === true ? "logged in" : x.authenticated === false ? "NOT logged in" : "login unknown (smoke-test will tell)";
      console.log(`  ${x.authenticated === false ? "✗" : "✓"} ${k} ${x.version} (${auth})`);
    }'
fi

echo
echo "$ok checks passed, $bad failed."
[ "$bad" -eq 0 ] && echo "Next: scripts/smoke-test.sh"
exit "$bad"
