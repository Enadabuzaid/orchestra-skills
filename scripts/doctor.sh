#!/usr/bin/env bash
# Checks that everything orchestrate needs is installed and wired up. Changes nothing.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json"
ok=0; bad=0; warnings=0
pass() { echo "  ✓ $1"; ok=$((ok + 1)); }
fail() { echo "  ✗ $1"; bad=$((bad + 1)); }
warn() { echo "  ! $1"; warnings=$((warnings + 1)); }
HAVE_NODE=0; HAVE_CLAUDE=0; CONFIG_VALID=0

printf '%s\n' "Base tools"
if command -v node >/dev/null 2>&1; then
  major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
  if [ "$major" -ge 18 ]; then HAVE_NODE=1; pass "node $(node --version)"; else fail "Node 18+ required (found $(node --version 2>/dev/null || echo unknown))"; fi
else
  fail "node not found (Node 18+ required)"
fi
command -v git >/dev/null 2>&1 && pass "git" || fail "git not found"
if command -v claude >/dev/null 2>&1; then HAVE_CLAUDE=1; pass "claude"; else fail "claude not found"; fi

printf '%s\n' "orchestra-skills"
[ -f "$CLAUDE_DIR/skills/orchestrate/SKILL.md" ] && pass "orchestrate skill" || fail "orchestrate skill missing: run ./install.sh"
for a in plan-reviewer diff-reviewer completion-auditor lane-runner; do
  [ -f "$CLAUDE_DIR/agents/$a.md" ] && pass "$a agent" || fail "$a agent missing: run ./install.sh"
done
grep -q "^## Orchestration (token budget)" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null && pass "CLAUDE.md rules" || fail "CLAUDE.md rules missing: run ./install.sh"

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
if [ -d "$CODEX_DIR" ]; then
  [ -f "$CODEX_DIR/skills/orchestrate-portable/SKILL.md" ] && pass "Codex: orchestrate-portable skill" || fail "Codex: orchestrate-portable missing: run ./install.sh"
fi

printf '%s\n' "delegate-skills"
for s in delegate-setup codex-delegate agy-delegate claude-delegate copilot-delegate; do
  [ -f "$CLAUDE_DIR/skills/$s/SKILL.md" ] && pass "$s" || fail "$s missing (see README install step 1)"
done

printf '%s\n' "Lanes ($CONFIG)"
if [ ! -f "$CONFIG" ]; then
  fail "no lane config: copy examples/lanes.json there or run delegate-setup"
elif [ "$HAVE_NODE" -ne 1 ]; then
  fail "cannot validate lane config without Node 18+"
else
  lane_output="$(node - "$CONFIG" 2>&1 <<'JS'
const fs = require('fs');
const path = process.argv[2];
let c;
try { c = JSON.parse(fs.readFileSync(path, 'utf8')); }
catch (e) { console.error(`invalid JSON: ${e.message}`); process.exit(2); }
if (!c || typeof c !== 'object' || !c.lanes || typeof c.lanes !== 'object' || Array.isArray(c.lanes)) {
  console.error('config must contain a lanes object'); process.exit(2);
}
const entries = Object.entries(c.lanes);
if (!entries.length) { console.error('lane config has no lanes'); process.exit(2); }
for (const [n, l] of entries) {
  if (!l || typeof l !== 'object' || typeof l.implementer !== 'string' || !l.implementer.trim()) {
    console.error(`lane ${n} is missing a non-empty implementer`); process.exit(2);
  }
  const dials = Object.entries(l).filter(([k]) => k !== 'implementer').map(([k,v]) => `${k}=${v}`).join(' ');
  console.log(`    ${n.padEnd(11)} → ${l.implementer.padEnd(8)} ${dials}`);
}
JS
)"
  lane_status=$?
  if [ "$lane_status" -eq 0 ]; then
    printf '%s\n' "$lane_output"
    CONFIG_VALID=1
    pass "lane config valid"
  else
    fail "lane config invalid: $(printf '%s' "$lane_output" | head -1)"
  fi
fi

printf '%s\n' "Claude billing / auth"
if [ "$HAVE_CLAUDE" -ne 1 ] || [ "$HAVE_NODE" -ne 1 ]; then
  fail "cannot check Claude auth without claude + Node"
elif [ -n "${ORCHESTRA_USE_API_KEY:-}" ]; then
  [ -n "${ANTHROPIC_API_KEY:-}" ] && pass "Claude lanes explicitly configured to use ANTHROPIC_API_KEY" || fail "ORCHESTRA_USE_API_KEY is set but ANTHROPIC_API_KEY is empty"
else
  auth_json="$(env -u ANTHROPIC_API_KEY claude auth status 2>/dev/null || true)"
  auth_method="$(printf '%s' "$auth_json" | node -e 'try{const a=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(a.authMethod||"")}catch{}' 2>/dev/null || true)"
  if [ -n "$auth_method" ]; then pass "Claude subscription login ($auth_method)"; else fail "Claude subscription auth not detected: run claude and log in"; fi
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then warn "ANTHROPIC_API_KEY is set in this shell; orchestra strips it from Claude lane/gate runs unless ORCHESTRA_USE_API_KEY=1"; fi
fi

printf '%s\n' "Implementer CLIs used by active lanes"
DISCOVER="$CLAUDE_DIR/skills/delegate-setup/scripts/discover.mjs"
if [ "$CONFIG_VALID" -ne 1 ]; then
  fail "cannot check active implementers until lane config is valid"
elif [ "$HAVE_NODE" -ne 1 ]; then
  fail "cannot run delegate discovery without Node 18+"
elif [ ! -f "$DISCOVER" ]; then
  fail "delegate discovery script missing: $DISCOVER"
else
  discover_json="$(node "$DISCOVER" 2>/dev/null || true)"
  if [ -z "$discover_json" ]; then
    fail "delegate discovery returned no data"
  else
    impl_output="$(DISCOVER_JSON="$discover_json" node - "$CONFIG" 2>&1 <<'JS'
const fs = require('fs');
const configPath = process.argv[2];
let d; try { d = JSON.parse(process.env.DISCOVER_JSON || ''); } catch (e) { console.error(`invalid discovery JSON: ${e.message}`); process.exit(2); }
const c = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const required = [...new Set(Object.values(c.lanes).map(x => x.implementer))];
let failed = false;
for (const k of required) {
  const x = (d.discovered || []).find(e => e.key === k);
  if (!x) { console.log(`  ✗ ${k}: not installed/discovered`); failed = true; continue; }
  const auth = x.authenticated === true ? 'logged in' : x.authenticated === false ? 'NOT logged in' : 'login unknown (smoke-test will verify)';
  const mark = x.authenticated === false ? '✗' : x.authenticated == null ? '!' : '✓';
  console.log(`  ${mark} ${k} ${x.version || ''} (${auth})`);
  if (x.authenticated === false) failed = true;
}
process.exit(failed ? 3 : 0);
JS
)"
    impl_status=$?
    printf '%s\n' "$impl_output"
    [ "$impl_status" -eq 0 ] && pass "active lane implementers discovered" || fail "one or more active lane implementers are unavailable or logged out"
  fi
fi

printf '\n%s\n' "$ok checks passed, $bad failed, $warnings warning(s)."
[ "$bad" -eq 0 ] && echo "Next: scripts/smoke-test.sh"
exit "$bad"
