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
for a in task-router plan-reviewer diff-reviewer completion-auditor lane-runner; do
  [ -f "$CLAUDE_DIR/agents/$a.md" ] && pass "$a agent" || fail "$a agent missing: run ./install.sh"
done
grep -q "^## Orchestration (token budget)" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null && pass "CLAUDE.md rules" || fail "CLAUDE.md rules missing: run ./install.sh"

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
if [ -d "$CODEX_DIR" ]; then
  [ -f "$CODEX_DIR/skills/orchestrate-portable/SKILL.md" ] && pass "Codex: orchestrate-portable skill" || fail "Codex: orchestrate-portable missing: run ./install.sh"
fi

printf '%s\n' "Orchestra policy"
ORCH="$(cd "$(dirname "$0")" && pwd)/orchestra"
if [ "$HAVE_NODE" -ne 1 ]; then
  fail "cannot read the policy without Node 18+"
elif ! check_out="$("$ORCH" check 2>&1)"; then
  fail "policy invalid: $(printf '%s' "$check_out" | sed -n '2p' | sed 's/^ *✗ *//')"
elif roles_out="$("$ORCH" roles --refresh 2>&1)"; then
  pass "policy valid ($(printf '%s' "$check_out" | sed 's/^policy OK: //; s/ (.*//'))"
  printf '%s\n' "$roles_out" | sed -n '2,$p' | sed '/^$/d' | sed 's/^/    /'
  none_roles="$(printf '%s\n' "$roles_out" | awk '/NONE AVAILABLE/{print $1}')"
  if [ -z "$none_roles" ]; then
    pass "every role has an available model"
  else
    fail "role(s) with no available model: $(printf '%s' "$none_roles" | tr '\n' ' ')"
    for r in $none_roles; do "$ORCH" resolve "$r" 2>&1 | sed 's/^/      /'; done
    echo "      fix: install/log in a tool, or change the chain (orchestra set <role> <model> …)"
  fi
  if printf '%s\n' "$roles_out" | grep -q "^Discovery:"; then warn "$(printf '%s\n' "$roles_out" | grep '^Discovery:')"; fi
else
  fail "orchestra roles failed: $(printf '%s' "${roles_out:-}" | head -1)"
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
  VALIDATE="$CLAUDE_DIR/skills/delegate-setup/scripts/config.mjs"
  if [ "$lane_status" -eq 0 ] && [ -f "$VALIDATE" ]; then
    # delegate-setup's validator also checks which settings each tool accepts, exactly as the relays do.
    if ! v_err="$(node "$VALIDATE" validate "$CONFIG" 2>&1 >/dev/null)"; then lane_output="$v_err"; lane_status=2; fi
  fi
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
  # Logged out still reports an authMethod ("none"), so require loggedIn === true.
  auth_method="$(printf '%s' "$auth_json" | node -e 'try{const a=JSON.parse(require("fs").readFileSync(0,"utf8"));if(a.loggedIn===true&&a.authMethod&&a.authMethod!=="none")process.stdout.write(String(a.authMethod))}catch{}' 2>/dev/null || true)"
  if [ -n "$auth_method" ]; then pass "Claude subscription login ($auth_method)"; else fail "Claude is not logged in with a subscription: run claude, then /login"; fi
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    # The scripts and lanes strip the key, but the main Claude Code session (and the plan-reviewer,
    # lane-runner and completion-auditor subagents inside it) only does so through a shell wrapper.
    if grep -qs 'env -u ANTHROPIC_API_KEY command claude' ~/.zshrc ~/.bashrc ~/.bash_profile ~/.config/fish/config.fish; then
      pass "ANTHROPIC_API_KEY is set, but your claude() wrapper keeps Claude Code on the subscription"
    else
      warn "ANTHROPIC_API_KEY is set: lanes/scripts ignore it, but your main Claude Code session (and its subagents) will bill it."
      warn "  Fix: add  claude() { env -u ANTHROPIC_API_KEY command claude \"\$@\"; }  to ~/.zshrc (or set ORCHESTRA_USE_API_KEY=1 if you want API billing)"
    fi
  fi
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

# Per-project readiness: doctor.sh <project-path>. Nothing is installed in a project; this only checks
# that orchestrate can run there (git, clean tree, the Antigravity write rule, a test command).
PROJECT="${1:-}"
if [ -n "$PROJECT" ]; then
  printf '%s\n' "Project: $PROJECT"
  if [ ! -d "$PROJECT" ]; then
    fail "no such folder"
  elif ! git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "not a git repository: orchestrate commits task by task and needs history to undo (git init first)"
  else
    pass "git repository ($(git -C "$PROJECT" rev-parse --short HEAD 2>/dev/null || echo 'no commits yet'))"
    if [ -z "$(git -C "$PROJECT" status --porcelain)" ]; then pass "clean working tree"; else warn "uncommitted changes: commit or stash before orchestrating, or they get mixed into task commits"; fi
    tests=""
    if [ -f "$PROJECT/artisan" ]; then tests="php artisan test"
    elif [ -f "$PROJECT/package.json" ] && node -e 'process.exit(require(process.argv[1]).scripts?.test?0:1)' "$PROJECT/package.json" 2>/dev/null; then tests="npm test"
    elif [ -f "$PROJECT/pytest.ini" ] || [ -f "$PROJECT/pyproject.toml" ]; then tests="pytest"
    elif [ -f "$PROJECT/go.mod" ]; then tests="go test ./..."
    elif [ -f "$PROJECT/Cargo.toml" ]; then tests="cargo test"; fi
    [ -n "$tests" ] && pass "test command detected: $tests (plans use the repo's real commands under Verify)" || warn "no test command detected; the plan's Verify section must name one"
    if [ "$HAVE_NODE" -eq 1 ] && "$ORCH" roles 2>/dev/null | awk '$0 ~ /antigravity/ && $0 !~ /NONE/ {f=1} END{exit f?0:1}'; then
      proj_real="$(cd "$PROJECT" && pwd -P)"
      if node -e 'const fs=require("fs"),p=process.env.HOME+"/.gemini/config/config.json";try{const a=JSON.parse(fs.readFileSync(p)).userSettings.globalPermissionGrants.allow||[];const t=process.argv[1];process.exit(a.some(r=>/^write_file\(/.test(r)&&(r.includes(`(${t})`)||t.startsWith(r.slice(11,-1)+"/")))?0:1)}catch{process.exit(1)}' "$proj_real" 2>/dev/null; then
        pass "Antigravity may write here"
      else
        warn "Antigravity has no write rule for this folder: $(cd "$(dirname "$0")" && pwd)/agy-allow.sh $PROJECT${tests:+ --tests \"$tests\"}"
      fi
    fi
  fi
fi

printf '\n%s\n' "$ok checks passed, $bad failed, $warnings warning(s)."
[ "$bad" -eq 0 ] && echo "Next: scripts/smoke-test.sh role:backend role:review   (a real task through the models the policy picks now)"
exit "$bad"
