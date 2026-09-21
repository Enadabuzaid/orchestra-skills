#!/usr/bin/env bash
# Smoke-test every delegation lane against a throwaway git repo.
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
  local lane="$1" impl ro dir out brief result status verdict=FAIL reason="" ro_violation="" unexpected=""
  impl="$(lane_field "$lane" implementer)"
  ro="$(lane_field "$lane" readOnly)"
  dir="$WORK/$lane"; out="$WORK/$lane.out"; brief="$WORK/$lane.brief.md"
  local relay="$SKILLS_DIR/$impl-delegate/scripts/relay.mjs"

  if [ -z "$impl" ]; then echo "$lane|?|FAIL|lane not in config" > "$WORK/$lane.row"; return; fi
  if [ ! -f "$relay" ]; then echo "$lane|$Impl|FAIL|$impl-delegate not installed" > "$WORK/$lane.row"; return; fi
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
2. Add a `multiply` test to math.test.js using node:test + node:assert, like the existing `add test.
3. Run `node --test` and make sure it passes.

## Do NOT
- Commit, push, or create branches.
- Create or modify any other file.

## Report back
Files changed and the `node --test` output.
EOF
  fi

  local start=$SECONDS

  local unset_key=(); [ "$impl" = "claude" ] && [ -z "${ORCHESTRA_USE_API_KEY:-}" ] && unset_key=(-u ANTHROPIC_API_KEY)
  env ${unset_key[@]+‰Ý[œÙ]ÚÙ^VÐ_HŸH›ÙH‰™[^HˆK[[™H‰[™HˆKXœšYYˆ‰œšYYˆˆKXÙ‰\ˆˆK][Y[Ý]‰SQSÕUˆK[Ý]Y\ˆ‰ÓÔ’ËÉ[™Kœ[ˆˆˆ‰Ý]ˆ‰ŒBˆØØ[ÙXÜÏI

ÑPÓÓ‘ÈHÝ\
JBˆ™\Ý[H‰ÓÔ’ËÉ[™Kœ[‹Ü™\Ý[šœÛÛˆ‚ˆÝ]\ÏH‰
›ÙHYH	Ýž^Ü›ØÙ\ÜËœÝÝ]Üš]J™\]Z\™J›ØÙ\ÜË˜\™Ý–ÌWJKœÝ]\ßˆŠ_XØ]ÚÜ›ØÙ\ÜËœÝÝ]Üš]J››Ë\™\Ý[Š_IÈ‰™\Ý[ŠH‚ˆ›×Ýš[Û][ÛH‰
›ÙHYH	Ýž^ØÛÛœÝ\™\]Z\™J›ØÙ\ÜË˜\™Ý–ÌWJKœ™XYÛ›Uš[Û][ÛŽÜ›ØÙ\ÜËœÝÝ]Üš]JOO]YOÈYHŽOOY˜[ÙOÈ™˜[ÙHŽˆ[šÛ›ÝÛˆŠ_XØ]ÚÜ›ØÙ\ÜËœÝÝ]Üš]J[šÛ›ÝÛˆŠ_IÈ‰™\Ý[ŠB‚ˆÙ‰\ˆˆ™]\›‚ˆØØ[ÛÛ[Z]ÈÚ[™ÙYˆÛÛ[Z]ÏH‰
Ú]™]‹[\ÝKXÛÝ[PQ
H‚ˆÚ[™ÙYH‰
Ú]Ý]\ÈK\Ü˜Ù[Z[ˆØÈ[ˆY	È	ÊH‚ˆ[™^XÝYH‰
Ú]Ý]\ÈK\Ü˜Ù[Z[ˆÙYQH	ÜË×‹‹‹ËÉÈÜ™\Q]ˆ	×ŠX]šœßX]\ÝšœÊI	ÈYJH‚‚ˆYˆÈ‰Ý]\ÈˆOH˜ÛÛ\]YˆH	‰ˆÜ™\\ZQHœ][Ý_˜]KÛ[Z]\ØYÙH[Z]ŸŽHˆ‰ÓÔ’ËÉ[™Kœ[ˆ‹Ê‹šœÛÛ›‰ÓÔ’ËÉ[™Kœ[ˆ‹ÜÝ\œ‹‰Ý]ˆ‹Ù]‹Û[È[‚ˆ™X\ÛÛH‰[\][ÝHÜˆ˜]H[Z]™XXÚYÈHÙ]\\Èš[™K™]žHY\ˆ]™\Ù]È
ÙYH	Ý]
H‚ˆ[YˆÈ‰Ý]\ÈˆOH˜ÛÛ\]YˆNÈ[ˆ™X\ÛÛHœ™[^HÝ]\Îˆ	Ý]\È
ÙYH	Ý]
H‚ˆ[YˆÈ‰ÛÛ[Z]ÈˆOHŒHˆNÈ[ˆ™X\ÛÛHš[\[Y[\ˆÛÛ[Z]Y
]\Ý›Ý
H‚ˆ[YˆÈ‰›ÈˆHYHˆNÈ[‚ˆYˆÈ‰›×Ýš[Û][ÛˆˆHYHˆNÈ[ˆ™X\ÛÛHœ™[^H]XÝYH™XY[Û›Hš[Û][Ûˆ‚ˆ[YˆÈ‰Ú[™ÙYˆOHŒˆNÈ[ˆ™X\ÛÛHœ™XY[Û›H[™HÚ[™ÙYš[\È‚ˆ[YˆH›ÙHYH	Ü›ØÙ\ÜË™^]
ØYË\Ý
™\]Z\™J›ØÙ\ÜË˜\™Ý–ÌWJK™š[˜[Y\ÜØYÙ_ˆŠOÌŒJIÈ‰™\Ý[ŽÈ[ˆ™X\ÛÛH˜[œÝÙ\ˆY›ÝY[[ÛˆY‚ˆ[ÙH™\™XÝTTÔÎÈ™X\ÛÛH˜[œÝÙ\™Y›ÈÚ[™Ù\ÈŽÈšBˆ[ÙBˆYˆÈ[ˆ‰[™^XÝYˆNÈ[ˆ™X\ÛÛH˜Ú[™ÙYš[JÊHÝ]ÚYHœšYYŽˆ	
š[ˆ	É\ÉÈ‰[™^XÝYˆˆ	×‰È	È	ÊH‚ˆ[YˆHÜ™\\H›][\HˆX]šœÎÈ[ˆ™X\ÛÛH›][\J
H›ÝYY‚ˆ[YˆH›ÙHK]\Ý‹Ù]‹Û[‰ŒNÈ[ˆ™X\ÛÛH››ÙHK]\Ý˜Z[È‚ˆ[YˆHÜ™\\H›][\HˆX]\ÝšœÎÈ[ˆ™X\ÛÛH››È][\H\Ý‚ˆ[ÙH™\™XÝTTÔÎÈ™X\ÛÛH›][\HYY\ÝÈÜ™Y[‹ØÛÜHÛX[‹›ÝÛÛ[Z]YŽÈšBˆšBˆXÚÈ‰[™_	[\	™\™XÝ	™X\ÛÛˆ
	ÜÙXÜß\ÊHˆˆ‰ÓÔ’ËÉ[™Kœ›ÝÈ‚ŸB‚™XÚÈ”Û[ÚÙK]\Ý[™È[™\Îˆ	ÓS‘TÖÊ—_H‚™XÚÈ•ÛÜšÈ\Žˆ	ÓÔ’È
[Y[Ý]\ˆ[™Nˆ	SQSÕU
H‚™XÚÂ“UOJ
B™›Üˆ[™H[ˆ‰ÓS‘TÖÐ_HŽÈÂˆYˆÈ‰
[™WÙšY[‰[™Hˆ[\[Y[\ŠHˆH˜ÛÜ[ÝˆNÈ[ˆUJÏJ‰[™HŠNÈ[ÙH[—Û[™H‰[™Hˆ	ˆšB™Û™BØZ]™›Üˆ[™H[ˆ	ÓUVÐJÈ‰ÓUVÐ_HŸNÈÈ[—Û[™H‰[™HŽÈÛ™B‚™˜Z[ÏLœš[ˆ	ÉKLM\È	KNÈ	KMœÈ	\×‰ÈS‘HÓÓ‘TÕSURS™›Üˆ[™H[ˆ‰ÓS‘TÖÐ_HŽÈÂˆQ”ÏIß	È™XY\ˆHˆˆ‰ÓÔ’ËÉ[™Kœ›ÝÈ‚ˆš[ˆ	ÉKLM\È	KNÈ	KMœÈ	\×‰È‰ˆ‰Hˆ‰ˆˆ‰ˆ‚ˆÈ‰ˆˆHTÔÈH˜Z[ÏI

˜Z[È
ÈJJB™Û™B™XÚÂ–È‰˜Z[ÈˆY\HH	‰ˆXÚÈ[[™\È\ÜÙYˆˆXÚÈ‰˜Z[È[™JÊH˜Z[YˆÙÜÎˆ	ÓÔ’È‚™^]‰˜Z[È‚