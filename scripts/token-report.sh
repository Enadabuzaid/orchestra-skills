#!/usr/bin/env bash
# Show which quota paid for each delegated run, so you can see what stayed off your Claude budget.
#
#   scripts/token-report.sh                 # every orchestrate run found on this machine
#   scripts/token-report.sh home-visit      # only runs for that project (repo folder name)
#   scripts/token-report.sh <run-dir> ...   # specific dirs passed to relay --out-dir
#
# Reads result.json + events.jsonl from each run. Changes nothing.
set -uo pipefail
# Arrays below use the ${a[@]+"${a[@]}"} form: macOS ships bash 3.2, where "${a[@]}" on an empty
# array is an "unbound variable" error under set -u.

if [ $# -eq 0 ] || { [ $# -eq 1 ] && [ ! -d "$1" ]; }; then
  name="${1:-}"; proj="${1:-*}"; shopt -s nullglob
  # Every result.json under the run folders (the runner nests run/, run2/, review/…).
  candidates=()
  while IFS= read -r f; do candidates+=("$(dirname "$f")"); done < <(
    find "${TMPDIR:-/tmp}"/orchestrate/$proj /tmp/orchestrate/$proj -name result.json 2>/dev/null)
  runs=()
  for d in ${candidates[@]+"${candidates[@]}"}; do
    [ -d "$d" ] || continue
    canon="$(cd "$d" 2>/dev/null && pwd -P)" || continue
    seen=0
    for existing in ${runs[@]+"${runs[@]}"}; do [ "$existing" = "$canon" ] && seen=1 && break; done
    [ "$seen" -eq 0 ] && runs+=("$canon")
  done
  [ ${#runs[@]} -gt 0 ] || { echo "No orchestrate runs found${name:+ for $name}."; exit 1; }
  set -- "${runs[@]}"
fi

node - "$@" <<'JS'
const fs = require("fs"), path = require("path");
const rows = [];
const quota = { codex: "ChatGPT", agy: "Google", copilot: "GitHub", claude: "Claude" };
const num = (n) => (n == null ? "–" : Number(n).toLocaleString("en-US"));

for (const dir of process.argv.slice(2)) {
  const resFile = path.join(dir, "result.json");
  if (!fs.existsSync(resFile)) continue;
  const r = JSON.parse(fs.readFileSync(resFile, "utf8"));
  const tool = r.tool || (r.codexVersion ? "codex" : r.agyVersion ? "agy" : r.copilotVersion ? "copilot" : r.claudeVersion ? "claude" : "unknown");
  let input = null, output = null, cost = null;
  const events = path.join(dir, "events.jsonl");
  const lines = fs.existsSync(events) ? fs.readFileSync(events, "utf8").split("\n").filter(Boolean) : [];
  for (const line of lines) {
    let e; try { e = JSON.parse(line); } catch { continue; }
    if (tool === "claude" && e.type === "result") {
      const u = e.usage || {};
      input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      output = u.output_tokens ?? null;
      cost = e.total_cost_usd ?? null;
    }
    if (tool === "codex" && e.usage) { input = e.usage.input_tokens; output = e.usage.output_tokens; }
    if (tool === "copilot" && e.type === "result" && e.usage) { output = e.usage.premiumRequests != null ? `${e.usage.premiumRequests} premium req` : null; }
  }
  if (tool === "claude" && input == null && r.usage) {
    const u = r.usage;
    input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
    output = u.output_tokens;
  }
  // Label = the path under /orchestrate/<repo>/ (e.g. "T2/review/run_uireview"), minus a trailing "/run".
  const m = dir.split("/orchestrate/")[1];
  const label = m ? m.split("/").slice(1).join("/").replace(/\/run$/, "") || path.basename(dir) : path.basename(dir);
  rows.push({ run: label, lane: r.lane || "–", tool, model: r.model || "default", status: r.status, input, output, cost, quota: quota[tool] || "?" });
}

if (!rows.length) { console.log("No result.json found in the given dirs."); process.exit(1); }
const pad = (s, n) => String(s).padEnd(n);
console.log(pad("RUN", 24) + pad("LANE", 16) + pad("TOOL", 8) + pad("MODEL", 22) + pad("STATUS", 11) + pad("IN TOKENS", 12) + pad("OUT", 9) + pad("USD", 8) + "PAID BY");
for (const x of rows) {
  console.log(pad(x.run.slice(0, 23), 24) + pad(x.lane.slice(0, 15), 16) + pad(x.tool, 8) + pad(String(x.model).slice(0, 21), 22) + pad(x.status, 11) +
    pad(num(x.input), 12) + pad(typeof x.output === "string" ? x.output : num(x.output), 9) + pad(x.cost == null ? "–" : "$" + x.cost.toFixed(3), 8) + x.quota);
}
const done = rows.filter((x) => x.status === "completed");
const offClaude = done.filter((x) => x.tool !== "claude" && x.tool !== "unknown").length;
const failed = rows.length - done.length;
const claudeCost = rows.filter((x) => x.cost != null).reduce((a, x) => a + x.cost, 0);
console.log(`\n${offClaude}/${done.length} completed runs used a non-Claude quota${failed ? ` (${failed} failed run(s) not counted: quota/permissions, then fallback)` : ""}. Claude lane spend: $${claudeCost.toFixed(3)}.`);
console.log("\"–\" means that CLI doesn't report the number. Antigravity keeps usage in its own account.");
JS
