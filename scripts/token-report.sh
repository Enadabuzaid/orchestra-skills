#!/usr/bin/env bash
# Show which quota paid for each delegated run, so you can see what stayed off your Claude budget.
#
#   scripts/token-report.sh <run-dir> [<run-dir> ...]     # dirs passed to relay --out-dir
#   scripts/token-report.sh "$TMPDIR"/delegate-relay/*    # default relay output location
#
# Reads result.json + events.jsonl from each run. Changes nothing.
set -uo pipefail
[ $# -ge 1 ] || { sed -n '2,7p' "$0"; exit 1; }

node - "$@" <<'JS'
const fs = require("fs"), path = require("path");
const rows = [];
const quota = { codex: "ChatGPT", agy: "Google", copilot: "GitHub", claude: "Claude" };
const num = (n) => (n == null ? "–" : Number(n).toLocaleString("en-US"));

for (const dir of process.argv.slice(2)) {
  const resFile = path.join(dir, "result.json");
  if (!fs.existsSync(resFile)) continue;
  const r = JSON.parse(fs.readFileSync(resFile, "utf8"));
  const tool = r.tool || (r.codexVersion ? "codex" : r.agyVersion ? "agy" : r.copilotVersion ? "copilot" : "claude");
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
  rows.push({ run: path.basename(dir), lane: r.lane || "–", tool, model: r.model || "default", status: r.status, input, output, cost, quota: quota[tool] || "?" });
}

if (!rows.length) { console.log("No result.json found in the given dirs."); process.exit(1); }
const pad = (s, n) => String(s).padEnd(n);
console.log(pad("RUN", 14) + pad("LANE", 10) + pad("TOOL", 8) + pad("MODEL", 22) + pad("STATUS", 11) + pad("IN TOKENS", 12) + pad("OUT", 9) + pad("USD", 8) + "PAID BY");
for (const x of rows) {
  console.log(pad(x.run.slice(0, 13), 14) + pad(x.lane, 10) + pad(x.tool, 8) + pad(String(x.model).slice(0, 21), 22) + pad(x.status, 11) +
    pad(num(x.input), 12) + pad(typeof x.output === "string" ? x.output : num(x.output), 9) + pad(x.cost == null ? "–" : "$" + x.cost.toFixed(3), 8) + x.quota);
}
const offClaude = rows.filter((x) => x.tool !== "claude").length;
const claudeCost = rows.filter((x) => x.cost != null).reduce((a, x) => a + x.cost, 0);
console.log(`\n${offClaude}/${rows.length} runs used a non-Claude quota. Claude lane spend: $${claudeCost.toFixed(3)} (Sonnet).`);
console.log("\"–\" means that CLI doesn't report the number. Antigravity keeps usage in its own account.");
JS
