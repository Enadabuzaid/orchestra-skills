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
[ -L "$HOME_A/orchestra-skills" ] && [ "$(cd "$HOME_A/orchestra-skills" && pwd -P)" = "$(cd "$ROOT" && pwd -P)" ] || fail "installer did not link ~/orchestra-skills to a checkout that lives elsewhere"
[ -L "$HOME_A/.local/bin/orchestra" ] || fail "installer did not put the orchestra command in ~/.local/bin"
[ "$(grep -c '<!-- orchestra-skills:start -->' "$CLAUDE_A/CLAUDE.md")" -eq 1 ] || fail "CLAUDE.md marker duplicated"
[ "$(grep -c '<!-- orchestra-skills:start -->' "$CODEX_A/AGENTS.md")" -eq 1 ] || fail "Codex marker duplicated"
before="$(find "$BK" -type f | wc -l | tr -d ' ')"
HOME="$HOME_A" CLAUDE_DIR="$CLAUDE_A" CODEX_HOME="$CODEX_A" XDG_CONFIG_HOME="$XDG_A" "$ROOT/install.sh" >/dev/null || fail "installer re-run exited non-zero"
after="$(find "$BK" -type f | wc -l | tr -d ' ')"
[ "$before" -eq "$after" ] || fail "re-running installer created unnecessary backups"
pass "installer backs up conflicts outside skill folders and is idempotent"

printf '%s\n' "Doctor"
for s in delegate-setup codex-delegate agy-delegate claude-delegate copilot-delegate; do mkdir -p "$CLAUDE_A/skills/$s/scripts"; : > "$CLAUDE_A/skills/$s/SKILL.md"; printf '%s\n' 'case "--read-only": case "--effort":' > "$CLAUDE_A/skills/$s/scripts/relay.mjs"; done
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

printf '%s\n' "Cards (minimum sufficient context)"
TPL="$ROOT/skills/orchestrate/references/brief-template.md"
for n in 1 2 3; do
  awk -v n="$n" '/^```markdown/{c++; if(c==n){f=1;next}} f&&/^```$/{f=0} f' "$TPL" > "$TMP/card$n.md"
  "$ROOT/scripts/brief-check.sh" "$TMP/card$n.md" >/dev/null || fail "brief-check rejected the template's example card #$n"
done
{ cat "$TMP/card1.md"; echo "As we discussed earlier in the chat, go with option A."; } > "$TMP/leak.md"
if "$ROOT/scripts/brief-check.sh" "$TMP/leak.md" >/dev/null 2>&1; then fail "brief-check accepted a card with leaked conversation context"; fi
grep -v "orchestrate or delegate" "$TMP/card1.md" > "$TMP/noguard.md"
if "$ROOT/scripts/brief-check.sh" "$TMP/noguard.md" >/dev/null 2>&1; then fail "brief-check accepted a task card that doesn't forbid orchestrating"; fi
grep -v "Already accepted" "$TMP/card2.md" > "$TMP/nodelta.md"
if "$ROOT/scripts/brief-check.sh" "$TMP/nodelta.md" >/dev/null 2>&1; then fail "brief-check accepted a delta retry without Already accepted"; fi
pass "task/delta/review cards pass; leaks, missing guard and incomplete deltas fail"

printf '%s\n' "Orchestra policy engine (fake tools, no model calls)"
OH="$TMP/orch-home"; mkdir -p "$OH/.claude/skills/delegate-setup/scripts"
# Fake relays declare the flags they accept, like the real ones do (each relay parses its own argv).
for t in codex claude agy opencode copilot; do mkdir -p "$OH/.claude/skills/$t-delegate/scripts"; printf '%s\n' 'case "--read-only": case "--effort": case "--variant":' > "$OH/.claude/skills/$t-delegate/scripts/relay.mjs"; done
mkdir -p "$OH/.claude/skills/kimi-delegate/scripts"; printf '%s\n' 'case "--model":' > "$OH/.claude/skills/kimi-delegate/scripts/relay.mjs"   # Kimi: no --read-only
cat > "$OH/.claude/skills/delegate-setup/scripts/discover.mjs" <<'JS'
if (process.env.FAKE_DISCOVER_FAIL) process.exit(1);
process.stdout.write(JSON.stringify({discovered:[
  {key:"codex",authenticated:true,models:{status:"reported",values:["gpt-6-astra","gpt-5.6-luna"]}},
  {key:"claude",authenticated:true,models:{status:"aliases",values:["fable","opus","sonnet","haiku"]}},
  {key:"agy",authenticated:true,models:{status:"reported",values:["gemini-3.8-flash-high\tGemini"]}},
  {key:"kimi",authenticated:true,models:{status:"unsupported",values:[]}},
  {key:"copilot",authenticated:null,models:{status:"unsupported",values:[]}}
]}));
JS
ORC() { HOME="$OH" XDG_CONFIG_HOME="$OH/.config" XDG_CACHE_HOME="$OH/.cache" "$ROOT/scripts/orchestra" "$@"; }
pick() { ORC resolve "$@" --json | node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0)).model))'; }
ORC check >/dev/null || fail "orchestra check rejected the default policy"
[ "$(pick backend)" = codex ] || fail "backend should resolve to codex when it's available"
[ "$(pick tests)" = kimi ] || fail "tests should resolve to kimi when its CLI is installed"
[ "$(pick docs)" = luna ] || fail "docs should skip deepseek (opencode CLI not installed) and use luna, never haiku as a builder"
ORC exhausted codex --for 60m >/dev/null
[ "$(pick backend)" = kimi ] || fail "backend should fall back to kimi while codex is exhausted"
[ "$(pick debug)" = sonnet ] || fail "debug should fall back to sonnet while codex is exhausted"
ORC available codex >/dev/null
[ "$(pick review --not-model luna)" = copilot ] || fail "review must skip the builder's model and use the next read-only reviewer (copilot)"
ORC resolve review --json | grep -q '"--read-only"' || fail "review must resolve read-only"
ORC resolve tests --json | grep -q '"--effort"' && fail "kimi's relay has no --effort; the engine must not pass it"
ORC exhausted copilot --for 60m >/dev/null
[ "$(pick review --not-model luna)" = haiku ] || fail "review must fall back past an exhausted copilot"
ORC available copilot >/dev/null
[ "$(pick security-review --cheap-only)" = copilot ] || fail "--cheap-only must skip expensive models"
# A read-only role never lands on a relay that can't enforce read-only (Kimi's has no --read-only).
ORC set planner-light kimi sonnet --read-only >/dev/null
[ "$(pick planner-light)" = sonnet ] || fail "a read-only role must skip a relay without --read-only"
ORC resolve planner-light 2>&1 | grep -q "no --read-only" || fail "the skip reason must say the relay has no --read-only"
if ORC check >/dev/null 2>&1; then fail "orchestra check accepted a read-only role that lists a relay without --read-only"; fi
ORC undo >/dev/null
ORC set docs copilot sonnet >/dev/null
if ORC check >/dev/null 2>&1; then fail "orchestra check accepted a writing role that uses the read-only-only copilot"; fi
ORC undo >/dev/null; ORC check >/dev/null || fail "orchestra undo did not restore a valid policy"
# A failed discovery must not be cached, and must not make every role unavailable.
rm -rf "$OH/.cache"
FAKE_DISCOVER_FAIL=1 ORC roles | grep -q "^Discovery:" || fail "a failed discovery must be reported"
[ ! -f "$OH/.cache/orchestra-skills/discover.json" ] || fail "a failed discovery was cached"
ORC roles >/dev/null; [ -f "$OH/.cache/orchestra-skills/discover.json" ] || fail "a good discovery was not cached"
[ "$(FAKE_DISCOVER_FAIL=1 pick backend)" = codex ] || fail "a failed refresh must keep using the last good discovery"
node -e 'const fs=require("fs");const f=process.argv[1];fs.writeFileSync(f,JSON.stringify({at:Date.now(),data:{discovered:[]}}))' "$OH/.cache/orchestra-skills/discover.json"
[ "$(pick backend)" = codex ] || fail "an empty cached discovery must be ignored and re-probed"
[ "$(ORC route simple planning)" = none ] || fail "route alias simple → tiny"
[ "$(ORC route small planner)" = planner-light ] || fail "small must use planner-light"
R="selftest-$$"; ORC budget start "$R" >/dev/null
ORC budget spend "$R" planner fable >/dev/null || fail "budget refused the planner call"
ORC budget spend "$R" architecture astra >/dev/null || fail "budget refused the second opinion"
ORC budget spend "$R" final-audit opus >/dev/null || fail "budget refused the final audit"
ORC budget spend "$R" backend sonnet >/dev/null || fail "budget must allow cheap calls"
if ORC budget spend "$R" security-review astra >/dev/null 2>&1; then fail "budget allowed a 4th expensive call"; fi
ORC metrics "$R" >/dev/null || fail "metrics failed for a run started without --dir"
pass "roles resolve by availability/quota/relay flags; builder≠reviewer; cheap-only; check; discovery never poisons; routing; budget refuses the 4th expensive call"

printf '%s\n' "Token report discovery"
RUNROOT="/tmp/orchestrate/orchestra-selftest-$$/T1/run"; mkdir -p "$RUNROOT"
printf '%s\n' '{"status":"completed","lane":"backend","tool":"codex","model":"test"}' > "$RUNROOT/result.json"
out="$(TMPDIR=/tmp "$ROOT/scripts/token-report.sh" "orchestra-selftest-$$" 2>&1)" || fail "token report crashed: $(printf '%s' "$out" | tail -1)"
[ "$(printf '%s\n' "$out" | grep -c '^T1[[:space:]]')" -eq 1 ] || fail "token report duplicated a /tmp run"
empty_out="$(TMPDIR="$TMP/no-runs" "$ROOT/scripts/token-report.sh" "no-such-project-$$" 2>&1 || true)"
printf '%s' "$empty_out" | grep -q "No orchestrate runs found for no-such-project-$$" || fail "token report crashed with no runs: $empty_out"
pass "token report deduplicates discovery paths and handles no runs"

printf '\nAll %s zero-quota checks passed.\n' "$ok"
