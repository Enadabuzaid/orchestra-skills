#!/usr/bin/env bash
# Check a task card before it's sent to an implementer: context isolation is enforced here.
#
#   scripts/brief-check.sh <card.md>            # exit 0 = OK to send
#   BRIEF_MAX_WORDS=600 scripts/brief-check.sh <card.md>
#
# Fails when a required section is missing, the card is too long, the Do-not block lacks the
# standard rules, or it contains signs of leaked context (conversation, old attempts, whole files).
set -uo pipefail

f="${1:?usage: brief-check.sh <card.md>}"
[ -f "$f" ] || { echo "brief-check: no such file: $f" >&2; exit 2; }
max="${BRIEF_MAX_WORDS:-450}"

node - "$f" "$max" <<'JS'
const fs = require("fs");
const [file, maxWords] = process.argv.slice(2);
const text = fs.readFileSync(file, "utf8");
const problems = [];

const words = (text.match(/\S+/g) || []).length;
const isDelta = /^TASK\s+\S+\s+\(round\s+\d+\)/m.test(text);
if (!/^TASK\s+\S+/m.test(text)) problems.push('missing the "TASK <ID>" header');

if (!isDelta) {
  for (const s of ["Goal:", "Files:", "Contract:", "Rules:", "Acceptance:", "Do not:"])
    if (!new RegExp(`^${s}`, "m").test(text)) problems.push(`missing section "${s}"`);
  const files = (text.split(/^Files:\s*$/m)[1] || "").split(/^\w[\w ]*:\s*$/m)[0].trim();
  if (!files) problems.push("Files: lists no paths");
}
const limit = isDelta ? Math.round(maxWords / 2) : Number(maxWords);
if (words > limit) problems.push(`${words} words (limit ${limit}): split the task or cut context`);

const doNot = (text.split(/^Do not:\s*$/m)[1] || "").toLowerCase();
if (!/commit/.test(doNot)) problems.push('Do not: must forbid committing');
if (!/depend/.test(doNot)) problems.push('Do not: must forbid dependency changes');
if (!isDelta && !/delegat|orchestrat/.test(doNot)) problems.push('Do not: must forbid orchestrating/delegating (workers load global rules too)');
if (!isDelta && !/you are the implementer|you are a reviewer|you are the reviewer/i.test(text)) problems.push('missing the "You are the implementer…" line under TASK');

// Signs that planning context leaked into the card.
const leaks = [
  [/\b(as (we|you) discussed|earlier in (the|this) (chat|conversation)|the user (said|wants|prefers))\b/i, "refers to the conversation"],
  [/\b(previous|earlier|last) (attempt|approach|version) (failed|didn't|did not)\b/i, "describes old attempts"],
  [/\b(alternatives? considered|we considered|option [AB]\b)/i, "contains architecture discussion"],
  [/^```[\s\S]{2500,}?^```/m, "pastes a large code block (give paths, not file contents)"],
];
for (const [re, why] of leaks) if (re.test(text)) problems.push(`context leak: ${why}`);

if (problems.length) {
  console.error(`brief-check: ${file}`);
  for (const p of problems) console.error(`  ✗ ${p}`);
  process.exit(1);
}
console.log(`brief-check: OK (${words} words${isDelta ? ", delta" : ""})`);
JS
