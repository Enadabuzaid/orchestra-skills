#!/usr/bin/env bash
# Enforce "minimum sufficient context" before a card is sent to any model.
#
#   scripts/brief-check.sh <card.md>      exit 0 = OK to send
#
# Recognises three card kinds (see skills/orchestrate/references/brief-template.md):
#   task card    "<ID> — <title>" (or "TASK <ID>")   needs Files, Acceptance, Don't
#   delta retry  "Continue <ID>."                   needs a failing check, Already accepted, Don't
#   review card  "Review <ID> …"                    needs Diff:, Check against, Reply
# Size limits come from the policy budget (briefs.max_tokens / reviews.max_tokens; tokens ≈ chars/4).
set -uo pipefail

f="${1:?usage: brief-check.sh <card.md>}"
[ -f "$f" ] || { echo "brief-check: no such file: $f" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="${XDG_CONFIG_HOME:-$HOME/.config}/orchestra-skills/orchestra.json"
[ -f "$POLICY" ] || POLICY="$ROOT/examples/orchestra.json"

node - "$f" "$POLICY" <<'JS'
const fs = require("fs");
const [file, policyFile] = process.argv.slice(2);
const text = fs.readFileSync(file, "utf8");
let budget = {}; try { budget = JSON.parse(fs.readFileSync(policyFile, "utf8")).budget || {}; } catch {}
const briefMax = budget.briefs?.max_tokens ?? 1500, reviewMax = budget.reviews?.max_tokens ?? 1000;
const tokens = Math.ceil(text.length / 4);
const problems = [];
const has = (re) => re.test(text);
const section = (name) => { const m = text.match(new RegExp(`^${name}:?[^\\n]*\\n([\\s\\S]*?)(?=^\\S[^\\n]*:\\s*$|$(?![\\s\\S]))`, "m")); return m ? m[0] : ""; };

let kind, limit;
if (has(/^Continue\s+\S+\.?\s*$/m)) {
  kind = "delta"; limit = Math.round(briefMax / 3);
  if (!has(/^(Only failing check|Failing check|Finding)s?:?/mi)) problems.push('delta needs "Only failing check:" (or the reviewer finding)');
  if (!has(/expected|actual|file:line|:\d+/i)) problems.push("delta needs expected/actual (or file:line)");
  if (!has(/^Already accepted:?/mi)) problems.push('delta needs "Already accepted:"');
} else if (has(/^Review\s+\S+/m)) {
  kind = "review"; limit = reviewMax;
  if (!has(/^Diff:/m)) problems.push('review card needs "Diff: <path>" (a path, not the diff itself)');
  if (!has(/^Check against:?/mi)) problems.push('review card needs "Check against:"');
  if (!has(/^Reply:?/mi)) problems.push('review card needs "Reply:"');
  if (has(/^(\+\+\+|---) [ab]\//m)) problems.push("review card pastes the diff; point to the file instead");
} else if (has(/^(TASK\s+)?[A-Z]+\d+\b/m)) {
  kind = "task"; limit = briefMax;
  for (const s of ["Files", "Acceptance"]) if (!has(new RegExp(`^${s}:`, "m"))) problems.push(`task card needs "${s}:"`);
  if (!has(/^(Rules|Contract):/m)) problems.push('task card needs "Rules:" and/or "Contract:"');
} else {
  problems.push('unrecognised card: start with "<ID> — <title>", "Continue <ID>." or "Review <ID>"');
  kind = "?"; limit = briefMax;
}

// Every card that can act must say what it may not do.
const dont = (text.split(/^(Don't|Do not)\b:?/mi)[2] || "").toLowerCase();
if (kind === "task" || kind === "delta") {
  if (!dont) problems.push(`missing "Don't:"`);
  else {
    if (!/commit/.test(dont)) problems.push("Don't: must forbid committing");
    if (!/depend/.test(dont)) problems.push("Don't: must forbid dependency changes");
    if (kind === "task" && !/orchestrat|delegat/.test(dont)) problems.push("Don't: must forbid orchestrating/delegating (workers load global rules too)");
  }
} else if (kind === "review" && !/edit|change|modify/.test(dont)) problems.push("Don't: must forbid editing");

if (tokens > limit) problems.push(`~${tokens} tokens > ${kind} limit ${limit}: cut context (minimum sufficient context)`);

const leaks = [
  [/\b(as (we|you) discussed|earlier in (the|this) (chat|conversation)|the user (said|wants|prefers))\b/i, "refers to the conversation"],
  [/\b(previous|earlier|last) (attempt|approach|version) (failed|didn't|did not)\b/i, "describes old attempts"],
  [/\b(alternatives? considered|we considered|option [AB]\b|business history)/i, "contains planning/business discussion"],
  [/^```[\s\S]{2500,}?^```/m, "pastes a large code block (give paths, not contents)"],
];
for (const [re, why] of leaks) if (re.test(text)) problems.push(`context leak: ${why}`);

if (problems.length) { console.error(`brief-check: ${file} (${kind})`); for (const p of problems) console.error(`  ✗ ${p}`); process.exit(1); }
console.log(`brief-check: OK (${kind}, ~${tokens} tokens, limit ${limit})`);
JS
