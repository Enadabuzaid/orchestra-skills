#!/usr/bin/env bash
# Smoke-test every delegation lane against a throwaway git repo.
#
#   scripts/smoke-test.sh                 # all lanes in your lane config
#   scripts/smoke-test.sh backend small   # only these lanes
#
# Each lane gets its own temp repo with math.js + a node:test file.
#  - write lanes must add multiply(), keep `node --test` green, and NOT commit.
#  - read-only lanes (readOnly: true) must answer and change nothing.
# Lanes run in parallel (copilot lanes run last). Nothing outside the temp dirs is touched.
set -uo pipefail

SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/delegate-skills/config.json"
TIMEOUT="${SMOKE_TIMEOUT:-10m}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orchestra-smoke.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"

[ -f "$CONFIG" ] || { echo "No lane config at $CONFIG. Run delegate-setup first."; exit 1; }

lane_field() { node -e 'const c=require(process.argv[1]).lanes[process.argv[2]]||{};const v=c[process.argv[3]];process.stdout.write(v===undefined?"":String(v))' "$CONFIG" "$1" "$2"; }

if [ $# -gt 0 ]; then LANES=("$@"); else
  # shellcheck disable=SC2207
  LANES=($(node -e 'console.log(Object.keys(require(process.argv[1]).lanes).join(" "))' "$CONFIG"))
fi

make_repo() {
  local dir="$1"
  mkdir -p "$dir" && cd "$dir" || return 1
  cat > math.js <<'EOF'
function add(a, b) {
  return a + b;
}

module.exports = { add };
EOF
  cat > math.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { add } = require('./math');

test('add', () => {
  assert.strictEqual(add(2, 3), 5);
});
EOF
  git init -q && git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m init
}

run_lane() {
  local lane="$1" impl ro dir out brief result status verdict=FAIL reason=""
  impl="$(lane_field "$lane" implementer)"
  ro="$(lane_field "$lane" readOnly)"
  dir="$WORK/$lane"; out="$WORK/$lane.out"; brief="$WORK/$lane.brief.md"
  local relay="$SKILLS_DIR/$impl-delegate/scripts/relay.mjs"

  if [ -z "$impl" ]; then echo "$lane|?|FAIL|lane not in config" > "$WORK/$lane.row"; return; fi
  if [ ! -f "$relay" ]; then echo "$lane|$impl|FAIL|$impl-delegate not installed" > "$WORK/$lane.row"; return; fi
  make_repo "$dir" >/dev/null 2>&1 || { echo "$lane|$impl|FAIL|could not create temp repo" > "$WORK/$lane.row"; return; }

  if [ "$ro" = "true" ]; then
    printf '%s\n' "Read-only task. Read math.js and reply with the names of the functions it exports, one per line. Do not edit any file." > "$brief"
  else
    cat > "$brief" <<'EOF'
# Task: add multiply()

## Goal
math.js exports multiply(a, b) returning a * b, with a test.

## Do
1. Add `multiply(a, b)` to math.js and export it next to `add`.
2. Add a `multiply` test to math.test.js using node:test + node:assert, like the existing `add` test.
3. Run `node --test` and make sure it passes.

## Do NOT
- Commit, push, or create branches.
- Create or modify any other file.

## Report back
Files changed and the `node --test` output.
EOF
  fi

  local start=$SECONDS
  # Claude lanes use your claude.ai subscription, not an API key (set ORCHESTRA_USE_API_KEY=1 to keep it).
  local unset_key=(); [ "$impl" = "claude" ] && [ -z "${ORCHESTRA_USE_API_KEY:-}" ] && unset_key=(-u ANTHROPIC_API_KEY)
  env ${unset_key[@]+"${unset_key[@]}"} node "$relay" --lane "$lane" --brief "$brief" --cd "$dir" --timeout "$TIMEOUT" --out-dir "$WORK/$lane.run" >"$out" 2>&1
  local secs=$((SECONDS - start))
  result="$WORK/$lane.run/result.json"
  status="$(node -e 'try{process.stdout.write(require(process.argv[1]).status||"")}catch{process.stdout.write("no-result")}' "$result")"

  cd "$dir" || return
  local commits changed
  commits="$(git rev-list --count HEAD)"
  changed="$(git status --porcelain | wc -l | tr -d ' ')"

  if [ "$status" != "completed" ] && grep -qiE "quota|rate.?limit|usage limit|402|429" "$WORK/$lane.run"/*.jsonl "$WORK/$lane.run"/stderr.txt "$out" 2>/dev/null; then
    reason="$impl quota or rate limit reached; the setup is fine, retry after it resets (see $out)"
  elif [ "$status" != "completed" ]; then reason="relay status: $status (see $out)"
  elif [ "$commits" != "1" ]; then reason="implementer committed (must not)"
  elif [ "$ro" = "true" ]; then
    if [ "$changed" != "0" ]; then reason="read-only lane changed files"
    elif ! node -e 'process.exit(/add/.test(require(process.argv[1]).finalMessage||"")?0:1)' "$result"; then reason="answer did not mention add"
    else verdict=PASS; reason="answered, no changes"; fi
  else
    if ! grep -q "multiply" math.js; then reason="multiply() not added"
    elif ! node --test >/dev/null 2>&1; then reason="node --test fails"
    elif ! grep -q "multiply" math.test.js; then reason="no multiply test"
    else verdict=PASS; reason="multiply added, tests green, not committed"; fi
  fi
  echo "$lane|$impl|$verdict|$reason (${secs}s)" > "$WORK/$lane.row"
}

echo "Smoke-testing lanes: ${LANES[*]}"
echo "Work dir: $WORK (timeout per lane: $TIMEOUT)"
echo
# Copilot's startup version check has a hard 10s limit that it can miss under heavy
# parallel load, so copilot lanes run after the others finish.
LATE=()
for lane in "${LANES[@]}"; do
  if [ "$(lane_field "$lane" implementer)" = "copilot" ]; then LATE+=("$lane"); else run_lane "$lane" & fi
done
wait
for lane in "${LATE[@]+"${LATE[@]}"}"; do run_lane "$lane"; done

fails=0
printf '%-15s %-8s %-6s %s\n' LANE TOOL RESULT DETAIL
for lane in "${LANES[@]}"; do
  IFS='|' read -r l i v r < "$WORK/$lane.row"
  printf '%-15s %-8s %-6s %s\n' "$l" "$i" "$v" "$r"
  [ "$v" = PASS ] || fails=$((fails + 1))
done
echo
[ "$fails" -eq 0 ] && echo "All lanes passed." || echo "$fails lane(s) failed. Logs: $WORK"
exit "$fails"
