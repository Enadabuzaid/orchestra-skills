#!/usr/bin/env bash
# End-to-end test: a fresh, unattended Claude Code session builds a 3-task feature on the demo app
# with the orchestrate skill. The script then checks the result itself, without trusting Claude's
# own report.
#
#   scripts/e2e-test.sh            # uses the ui lane (Antigravity) for the renderer task
#   scripts/e2e-test.sh --no-ui    # sends the renderer task to the backend job instead
#   scripts/e2e-test.sh --codex    # Codex (gpt-6-astra) is the orchestrator, using orchestrate-portable:
#                                  # Claude gates via the plan-gate / done-gate lanes
#
# Everything happens in a throwaway git repo under $TMPDIR. Takes ~10-25 minutes and uses real
# quota: Opus for planning and the gates, plus Codex / Antigravity / Sonnet for the coding.
# Claude runs headless with file and shell tools allowed, limited to that temp repo by the prompt.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI_LANE="frontend"; ORCH="claude"
for a in "$@"; do case "$a" in --no-ui) UI_LANE="backend" ;; --codex) ORCH="codex" ;; esac; done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orchestra-e2e.XXXXXX")"; WORK="$(cd "$WORK" && pwd -P)"
REPO="$WORK/e2e-demo-${WORK##*.}"; LOG="$WORK/claude.json"   # unique name: relay run dirs are named after it
MODEL="${E2E_MODEL:-opus}"

step() { printf '\n== %s\n' "$1"; }
ok=0; bad=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  ✓ $1"; ok=$((ok + 1)); else echo "  ✗ $1"; bad=$((bad + 1)); fi; }

step "1. Preflight"
"$ROOT/scripts/doctor.sh" >/dev/null 2>&1 && echo "  ✓ doctor passed" || { echo "  ✗ doctor failed; run scripts/doctor.sh"; exit 1; }

step "2. Demo repo at $REPO"
cp -R "$ROOT/examples/demo-app" "$REPO" && cd "$REPO" || exit 1
git init -q && git add -A && git -c user.name=e2e -c user.email=e2e@example.com commit -qm "chore: demo baseline"
BASE="$(git rev-parse --short HEAD)"; echo "  base commit $BASE"
# Give Antigravity scoped rights in the throwaway repo whenever any lane uses it.
if node -e 'const c=require(process.argv[1]);process.exit(Object.values(c.lanes).some(l=>l.implementer==="agy")?0:1)' "${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json" 2>/dev/null; then
  "$ROOT/scripts/agy-allow.sh" "$REPO" --tests "node" | sed 's/^/  /'
fi

step "3. Unattended orchestrate run (orchestrator: $ORCH, ui task → $UI_LANE lane)"
SKILL_NAME="orchestrate"; [ "$ORCH" = "codex" ] && SKILL_NAME="orchestrate-portable"
PROMPT="Use the $SKILL_NAME skill to implement this feature in the current repo ($REPO). This is an
unattended, headless test (claude -p): never ask questions, make sensible decisions yourself, and only
touch files inside $REPO. Your process exits as soon as you end your reply, which kills any background
job, so never end your reply until the completion-auditor has given its final verdict.
Commit with plain messages and no Co-Authored-By trailer.

Feature: todos can have due dates.
- T1 (job backend): add(title, { due }) where due is optional YYYY-MM-DD (null/undefined → null; reject
  invalid or impossible dates such as 2026-02-30 with 'invalid due date'), and overdue(today) that returns
  open todos with due < today, ordered by due then id.
- T2 (job $UI_LANE): render.js exporting renderTodos(todos, today), which returns an HTML string with
  done/overdue classes and escaped titles, plus render.test.js and a static index.html. Runs in parallel
  with T1.
- T3 (job docs): README.md documenting the API, after T1 and T2.

Follow the skill exactly: route the request, get the plan from the planner lane (with the
architecture review if the route requires it), build with task cards, and finish with the final
audit loop. The plan needs a Definition of Done and Verify commands (node --test and a node -e
runtime check).
As the very last line of your reply, print exactly one of:
E2E-RESULT: DONE
E2E-RESULT: GAPS"
START=$SECONDS
# Use the claude.ai subscription, not an API key (set ORCHESTRA_USE_API_KEY=1 to keep the key).
UNSET_KEY=(-u ANTHROPIC_API_KEY); [ -n "${ORCHESTRA_USE_API_KEY:-}" ] && UNSET_KEY=()
if [ "$ORCH" = "codex" ]; then
  # The orchestrating Codex must start relays that reach the network and write CLI session files,
  # so it needs full access. This only runs against the throwaway repo above.
  env ${UNSET_KEY[@]+"${UNSET_KEY[@]}"} codex exec -m "${E2E_CODEX_MODEL:-gpt-6-astra}" -C "$REPO" -s danger-full-access \
    -o "$WORK/last-message.txt" "$PROMPT" > "$WORK/codex.log" 2>&1
  node -e 'const fs=require("fs");const m=fs.existsSync(process.argv[2])?fs.readFileSync(process.argv[2],"utf8"):"";fs.writeFileSync(process.argv[1],JSON.stringify({result:m}))' "$LOG" "$WORK/last-message.txt"
else
  env -u CLAUDECODE ${UNSET_KEY[@]+"${UNSET_KEY[@]}"} claude -p "$PROMPT" --model "$MODEL" --output-format json \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Agent,Task,Skill" > "$LOG" 2>"$WORK/claude.err"
fi
echo "  finished in $(( (SECONDS - START) / 60 ))m $(( (SECONDS - START) % 60 ))s (log: $LOG)"

if [ "$ORCH" = "codex" ] && grep -qiE "usage limit|rate limit|quota" "$WORK/codex.log" 2>/dev/null && [ ! -s "$WORK/last-message.txt" ]; then
  echo "  ! Codex stopped before starting: $(grep -iE -m1 'usage limit|rate limit|quota' "$WORK/codex.log" | cut -c1-160)"
  echo "    That's a quota problem, not a workflow bug. Re-run after it resets."
  exit 3
fi
if node -e "const r=require('$LOG');process.exit((r.is_error||/^\\s*API Error/.test(r.result||''))?0:1)" 2>/dev/null; then
  echo "  ! Claude stopped with an API error: $(node -e "console.log((require('$LOG').result||'').slice(0,160))")"
  echo "    That's an account or quota problem, not a workflow bug. Fix it and re-run."
fi

step "4. Checks (run by this script, not by Claude)"
cd "$REPO" || exit 1
PLAN="$(ls docs/plans/*.md 2>/dev/null | head -1)"
check "plan written to docs/plans/"                 "[ -n '$PLAN' ]"
check "plan has a Definition of Done"               "grep -qi 'definition of done' '$PLAN'"
check "plan has Verify commands"                    "grep -qi '^## verify' '$PLAN'"
check "T1: overdue() implemented"                   "grep -q 'overdue' todos.js"
check "T1: impossible dates rejected"               "node -e \"const {createStore}=require('./todos');try{createStore().add('x',{due:'2026-02-30'});process.exit(1)}catch(e){process.exit(/invalid due date/.test(e.message)?0:1)}\""
check "T1: overdue order + exclusions"              "node -e \"const {createStore}=require('./todos');const s=createStore();s.add('b',{due:'2026-01-02'});s.add('a',{due:'2026-01-01'});s.add('c',{due:'2026-09-21'});s.add('d');const r=s.overdue('2026-09-21').map(t=>t.title).join();process.exit(r==='a,b'?0:1)\""
check "T2: renderer escapes and marks overdue"      "node -e \"const {renderTodos}=require('./render');const h=renderTodos([{id:1,title:'<b>x</b>',done:false,due:'2026-01-01'}],'2026-09-21');process.exit(h.includes('overdue')&&!h.includes('<b>')?0:1)\""
check "T2: index.html exists"                       "[ -f index.html ]"
check "T3: README.md exists"                        "[ -s README.md ]"
check "full test suite passes"                      "node --test"
check "more tests than the 3 in the baseline"       "[ \$(node --test 2>&1 | awk '/^# tests/{print \$3}') -gt 3 ]"
check "work is committed (clean tree)"              "[ -z \"\$(git status --porcelain)\" ]"
check "at least 4 commits after the baseline"       "[ \$(git rev-list --count $BASE..HEAD) -ge 4 ]"
check "no Co-Authored-By trailers"                  "! git log --format=%B | grep -qi 'co-authored-by'"
check "completion-auditor verdict: DONE"            "node -e \"const r=require('$LOG');process.exit(/E2E-RESULT: DONE\\s*\$/.test(r.result||'')?0:1)\""
RUNS=()
while IFS= read -r f; do RUNS+=("$(dirname "$f")"); done < <(
  find "${TMPDIR:-/tmp}/orchestrate/$(basename "$REPO")" "/tmp/orchestrate/$(basename "$REPO")" \
       "${TMPDIR:-/tmp}"/delegate-relay/"$(basename "$REPO")"-* -name result.json 2>/dev/null | sort -u)
check "coding was delegated (relay runs found)"     "[ ${#RUNS[@]} -gt 0 ]"
# grep over the files directly: with pipefail, `cat … | grep -q` fails as soon as grep matches (cat gets SIGPIPE).
check "some coding ran on a non-Claude quota"       "[ ${#RUNS[@]} -gt 0 ] && grep -q -e codexVersion -e agyVersion -e opencodeVersion -e kimiVersion -- ${RUNS[*]+${RUNS[*]/%//result.json}}"

step "5. Commits"
git log --oneline "$BASE..HEAD" | sed 's/^/  /'

step "6. Cost"
node -e '
  const r = require(process.argv[1]);
  const u = r.usage || {};
  const inTok = (u.input_tokens||0) + (u.cache_creation_input_tokens||0) + (u.cache_read_input_tokens||0);
  console.log(`  Claude orchestrator + subagents: $${(r.total_cost_usd||0).toFixed(2)}  (${inTok.toLocaleString("en-US")} in / ${(u.output_tokens||0).toLocaleString("en-US")} out tokens, ${r.num_turns} turns)`);
  if (r.modelUsage) for (const [m, v] of Object.entries(r.modelUsage))
    console.log(`    ${m.padEnd(28)} $${(v.costUSD||0).toFixed(2)}`);
' "$LOG" 2>/dev/null || echo "  (no cost data in $LOG)"
[ ${#RUNS[@]} -gt 0 ] && "$ROOT/scripts/token-report.sh" ${RUNS[@]+"${RUNS[@]}"} | sed 's/^/  /'

step "Result"
echo "  $ok checks passed, $bad failed. Work dir: $WORK"
exit "$bad"
