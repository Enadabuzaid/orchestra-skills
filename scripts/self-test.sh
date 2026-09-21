#!/usr/bin/env bash
# Zero-quota checks for orchestra-skills itself. Safe for CI: no external model/CLI calls.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/orchestra-selftest.XXXXXX")"
trap 'rm -rf "$TMP" "/tmp/orchestrate/orchestra-selftest-$$"' EXIT
ok=0
pass() { echo "  ✓ $1"; ok=$((ok + 1)); }
fail() { echo "  ✗ $1" >&2; exit 1; }

printf '%s\n' "Shell syntax"
for f in "$ROOT"/install.sh "$ROOT"/scripts/*.sh; do
  bash -n "$f" || fail "bash syntax: ${f#$ROOT/}"
done
pass "all shell scripts parse"

printf '%s\n' "JSON + demo"
node -e 'const fs=require("fs");for(const f of process.argv.slice(1)) JSON.parse(fs.readFileSync(f,"utf8"))' "$ROOT"/examples/lanes*.json || fail "lane preset JSON"
pass "lane preset JSON parses"
( cd "$ROOT/examples/demo-app" && node --test ) >/dev/null || fail "demo app tests"
pass "demo app tests"

printf '%s\n' "Installer safety / idempotence"
HOME_A="$TMP/home-install"; CLAUDE_A="$HOME_A/.claude"; CODEX_A="$HOME_A/.codex"; XDG_A="$HOME_A/.config"
BK="$XDG_A/orchestra-skills/backups"
mkdir -p "$CLAUDE_A/agents" "$CLAUDE_A/skills/orchestrate" "$CODEX_A"
printf '%s\n' "user agent file" > "$CLAUDE_A/agents/plan-reviewer.md"
printf '%s\n' "---" "name: orchestrate" "description: an older copy (e.g. from npx skills add)" "---" > "$CLAUDE_A/skills/orchestrate/SKILL.md"
printf '%s\n' "# My Claude rules" > "$CLAUDE_A/CLAUDE.md"
printf '%s\n' "# My Codex rules" > "$CODEX_A/AGENTS.md"
HOME="$HOME_A" CLAUDE_DIR="$CLAUDE_A" CODEX_HOME="$CODEX_A" XDG_CONFIG_HOME="$XDG_A" "$ROOT/install.sh" >/dev/null || fail "installer exited non-zero"
[ -L "$CLAUDE_A/agents/plan-reviewer.md" ] || fail "installer did not replace conflict with symlink"
[ -L "$CLAUDE_A/skills/orchestrate" ] || fail "installer did not replace the old skill folder with a link"
ls "$BK"/*/.claude/agents/plan-reviewer.md >/dev/null 2>&1 || fail "installer did not back up conflicting agent"
ls "$BK"/*/.claude/skills/orchestrate/SKILL.md >/dev/null 2>&1 || fail "installer did not back up the old skill folder"
ls "$BK"/*/.claude/CLAUDE.md >/dev/null 2>&1 || fail "installer did not back up CLAUDE.md"
ls "$BK"/*/.codex/AGENTS.md >/dev/null 2>&1 || fail "installer did not back up Codex AGENTS.md"
# A backup left inside a skills/agents folder would be loaded as a duplicate skill or agent.
[ -z "$(find "$CLAUDE_A" "$CODEX_A" -name '*backup*' 2>/dev/null)" ] || fail "installer left backups inside ~/.claude or ~/.codex"
dupes="$(find -L "$CLAUDE_A/skills" -name SKILL.md -exec grep -l '^name: orchestrate$' {} + 2>/dev/null | wc -l | tr -d ' ')"
[ "$dupes" -eq 1 ] || fail "found $dupes skills named orchestrate in ~/.claude/skills (expected 1)"
[ "$(grep -c '<!-- orchestra-skills:start -->' "$CLAUDE_A/CLAUDE.md")" -eq 1 ] || fail "CLAUDE.md marker duplicated"
[ "$(grep -c '<!-- orchestra-skills:start -->' "$CODEX_A/AGENTS.md")" -eq 1 ] || fail "Codex marker duplicated"
before="$(find "$BK" -type f | wc -l | tr -d ' ')"
HOME="$HOME_A" CLAUDE_DIR="$CLAUDE_A" CODEX_HOME="$CODEX_A" XDG_CONFIG_HOME="$XDG_A" "$ROOT/install.sh" >/dev/null || fail "installer re-run exited non-zero"
after="$(find "$BK" -type f | wc -l | tr -d ' ')"
[ "$before" -eq "$after" ] || fail "re-running installer created unnecessary backups"
pass "installer backs up conflicts outside skill folders and is idempotent"

printf '%s\n' "Doctor"
for s in delegate-setup codex-delegate agy-delegate claude-delegate copilot-delegate; do mkdir -p "$CLAUDE_A/skills/$s"; : > "$CLAUDE_A/skills/$s/SKILL.md"; done
mkdir -p "$CLAUDE_A/skills/delegate-setup/scripts" "$TMP/bin"
cat > "$CLAUDE_A/skills/delegate-setup/scripts/discover.mjs" <<'JS'
process.stdout.write(JSON.stringify({discovered:[
  {key:'codex',version:'test',authenticated:true},
  {key:'agy',version:'test',authenticated:true},
  {key:'claude',version:'test',authenticated:true},
  {key:'copilot',version:'test',authenticated:true}
]}));
JS
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  if [ -n "${FAKE_CLAUDE_LOGGED_OUT:-}" ]; then echo '{"loggedIn":false,"authMethod":"none"}'; else echo '{"loggedIn":true,"authMethod":"claude.ai"}'; fi
  exit 0
fi
exit 0
SH
chmod +x "$TMP/bin/claude"
PATH="$TMP/bin:$PATH" HOME="$HOME_A" CLAUDE_DIR="$CLAUDE_A" CODEX_HOME="$CODEX_A" XDG_CONFIG_HOME="$XDG_A" "$ROOT/scripts/doctor.sh" >/dev/null || fail "doctor rejected valid fake setup"
cp "$XDG_A/delegate-skills/config.json" "$TMP/good-config.json"
printf '%s\n' '{not json' > "$XDG_A/delegate-skills/config.json"
if PATH="$TMP/bin:$PATH" HOME="$HOME_A" CLAUDE_DIR="$CLAUDE_A" CODEX_HOME="$CODEX_A" XDG_CONFIG_HOME="$XDG_A" "$ROOT/scripts/doctor.sh" >/dev/null 2>&1; then fail "doctor accepted invalid lane JSON"; fi
cp "$TMP/good-config.json" "$XDG_A/delegate-skills/config.json"
if FAKE_CLAUDE_LOGGED_OUT=1 PATH="$TMP/bin:$PATH" HOME="$HOME_A" CLAUDE_DIR="$CLAUDE_A" CODEX_HOME="$CODEX_A" XDG_CONFIG_HOME="$XDG_A" "$ROOT/scripts/doctor.sh" >/dev/null 2>&1; then fail "doctor accepted a logged-out Claude"; fi
pass "doctor accepts valid setup; rejects invalid lanes and logged-out Claude"

printf '%s\n' "Smoke-test scope enforcement"
SMOKE_HOME="$TMP/home-smoke"; SMOKE_SKILLS="$SMOKE_HOME/.claude/skills"; SMOKE_CFG="$SMOKE_HOME/.config/delegate-skills"
mkdir -p "$SMOKE_SKILLS/fake-delegate/scripts" "$SMOKE_CFG"
cat > "$SMOKE_CFG/config.json" <<'JSON'
{"version":"delegate-fleet.v1","lanes":{"backend":{"implementer":"fake"}}}
JSON
cat > "$SMOKE_SKILLS/fake-delegate/scripts/relay.mjs" <<'JS'
import fs from 'node:fs'; import path from 'node:path';
const args=process.argv.slice(2); const val=(k)=>args[args.indexOf(k)+1]; const cd=val('--cd'), out=val('--out-dir');
fs.writeFileSync(path.join(cd,'math.js'), 'function add(a,b){return a+b;}\nfunction multiply(a,b){return a*b;}\nmodule.exports={add,multiply};\n');
fs.writeFileSync(path.join(cd,'math.test.js'), "const test=require('node:test');const assert=require('node:assert');const {add,multiply}=require('./math');test('add',()=>assert.strictEqual(add(2,3),5));test('multiply',()=>assert.strictEqual(multiply(2,3),6));\n");
if (process.env.SELFTEST_SMOKE_EXTRA === '1') fs.writeFileSync(path.join(cd,'oops.txt'),'out of scope\n');
fs.mkdirSync(out,{recursive:true}); fs.writeFileSync(path.join(out,'result.json'), JSON.stringify({status:'completed',lane:'backend',tool:'fake',finalMessage:'done',touchedFiles:[]}));
JS
if SELFTEST_SMOKE_EXTRA=1 SKILLS_DIR="$SMOKE_SKILLS" XDG_CONFIG_HOME="$SMOKE_HOME/.config" "$ROOT/scripts/smoke-test.sh" backend >/dev/null 2>&1; then fail "smoke test accepted an out-of-scope file"; fi
SKILLS_DIR="$SMOKE_SKILLS" XDG_CONFIG_HOME="$SMOKE_HOME/.config" "$ROOT/scripts/smoke-test.sh" backend >/dev/null || fail "smoke test rejected valid scoped changes"
pass "smoke test rejects out-of-scope writes"

printf '%s\n' "Antigravity permission helper"
AGY_HOME="$TMP/home-agy"; PROJECT="$TMP/project"; mkdir -p "$AGY_HOME/.gemini/config" "$AGY_HOME/.gemini/antigravity-cli" "$PROJECT"
PROJECT="$(cd "$PROJECT" && pwd -P)"   # agy-allow records the resolved path (macOS: /var -> /private/var)
printf '%s\n' '{}' > "$AGY_HOME/.gemini/config/config.json"
printf '%s\n' '{}' > "$AGY_HOME/.gemini/antigravity-cli/settings.json"
HOME="$AGY_HOME" "$ROOT/scripts/agy-allow.sh" "$PROJECT" --tests "node --test" >/dev/null || fail "agy-allow.sh exited non-zero"
node - "$AGY_HOME" "$PROJECT" <<'JS' || fail "agy-allow.sh did not add the scoped rules to both config files"
const fs=require('fs'),path=require('path'); const [home,project]=process.argv.slice(2);
const a=JSON.parse(fs.readFileSync(path.join(home,'.gemini/config/config.json'))).userSettings.globalPermissionGrants.allow;
const b=JSON.parse(fs.readFileSync(path.join(home,'.gemini/antigravity-cli/settings.json'))).permissions.allow;
for (const arr of [a,b]) { if (!arr.includes(`write_file(${project})`) || !arr.some(x=>x.startsWith('command(regex:node --test'))) process.exit(1); }
JS
pass "Antigravity helper updates both known config schemas"

printf '%s\n' "Token report discovery"
RUNROOT="/tmp/orchestrate/orchestra-selftest-$$/T1/run"; mkdir -p "$RUNROOT"
printf '%s\n' '{"status":"completed","lane":"backend","tool":"codex","model":"test"}' > "$RUNROOT/result.json"
out="$(TMPDIR=/tmp "$ROOT/scripts/token-report.sh" "orchestra-selftest-$$" 2>&1)" || fail "token report crashed: $(printf '%s' "$out" | tail -1)"
[ "$(printf '%s\n' "$out" | grep -c '^T1[[:space:]]')" -eq 1 ] || fail "token report duplicated a /tmp run"
empty_out="$(TMPDIR="$TMP/no-runs" "$ROOT/scripts/token-report.sh" "no-such-project-$$" 2>&1 || true)"
printf '%s' "$empty_out" | grep -q "No orchestrate runs found for no-such-project-$$" || fail "token report crashed with no runs: $empty_out"
pass "token report deduplicates discovery paths and handles no runs"

printf '\nAll %s zero-quota checks passed.\n' "$ok"
