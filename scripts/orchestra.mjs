#!/usr/bin/env node
// orchestra: the policy engine. ROLE → MODEL with fallbacks, routing levels, token budget and run
// metrics. Reads ~/.config/orchestra-skills/orchestra.json (or the repo default).
// Node built-ins only.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const HOME = os.homedir();
const CFG_DIR = path.join(process.env.XDG_CONFIG_HOME || path.join(HOME, ".config"), "orchestra-skills");
const USER_POLICY = path.join(CFG_DIR, "orchestra.json");
const DEFAULT_POLICY = path.join(ROOT, "examples", "orchestra.json");
const STATE = path.join(CFG_DIR, "state.json");
const CACHE_DIR = path.join(process.env.XDG_CACHE_HOME || path.join(HOME, ".cache"), "orchestra-skills");
const SKILL_DIRS = [path.join(HOME, ".claude", "skills"), path.join(HOME, ".codex", "skills"), path.join(HOME, ".agents", "skills")];
const ROLE_ALIASES = { "code-review": "review", "architecture-review": "architecture", "architecture-review-alt": "architecture", ui: "frontend", "ui-check": "ui-review", "plan-check": "architecture", "done-gate": "final-audit", "final_audit": "final-audit" };
const LEVEL_ALIASES = { simple: "tiny", medium: "feature", "very-complex": "complex" };

const die = (msg, code = 1) => { process.stderr.write(`orchestra: ${msg}\n`); process.exit(code); };
const readJSON = (f, fallback) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return fallback; } };
const writeJSON = (f, v) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(v, null, 2) + "\n"); };
const policyPath = () => (fs.existsSync(USER_POLICY) ? USER_POLICY : DEFAULT_POLICY);
const loadPolicy = () => { const p = readJSON(policyPath(), null); if (!p || !p.roles || !p.models) die(`invalid policy: ${policyPath()}`); return p; };
const savePolicy = (p) => {
  if (fs.existsSync(USER_POLICY)) { const b = path.join(CFG_DIR, "backups"); fs.mkdirSync(b, { recursive: true }); fs.copyFileSync(USER_POLICY, path.join(b, `orchestra.${Date.now()}.json`)); }
  writeJSON(USER_POLICY, p);
};
const roleName = (r) => ROLE_ALIASES[r] || r;

// ---------- availability ----------
function discover(refresh) {
  const f = path.join(CACHE_DIR, "discover.json");
  const c = readJSON(f, null);
  if (!refresh && c && Date.now() - c.at < 15 * 60 * 1000) return c.data;
  const script = SKILL_DIRS.map((d) => path.join(d, "delegate-setup", "scripts", "discover.mjs")).find((p) => fs.existsSync(p));
  let data = { discovered: [] };
  if (script) { try { data = JSON.parse(execFileSync("node", [script], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 120000 })); } catch {} }
  writeJSON(f, { at: Date.now(), data });
  return data;
}
const relayFor = (tool) => SKILL_DIRS.map((d) => path.join(d, `${tool}-delegate`, "scripts", "relay.mjs")).find((p) => fs.existsSync(p));
function exhaustedUntil(tool) {
  const s = readJSON(STATE, { exhausted: {} }); const u = s.exhausted?.[tool];
  return u && new Date(u) > new Date() ? u : null;
}
function availability(name, p, disc) {
  const m = p.models[name];
  if (!m) return `unknown model "${name}" (add it under "models")`;
  if (!relayFor(m.tool)) return `${m.tool}-delegate skill not installed`;
  const d = disc.discovered?.find((e) => e.key === m.tool);
  if (!d) return `${m.tool} CLI not installed`;
  if (d.authenticated === false) return `${m.tool} not logged in`;
  if (m.model && d.models?.status === "reported") {
    const ids = (d.models.values || []).map((v) => String(v).split("\t")[0]);
    if (!ids.includes(m.model)) return `model ${m.model} not offered by ${m.tool}`;
  }
  const u = exhaustedUntil(m.tool); if (u) return `${m.tool} quota exhausted until ${new Date(u).toLocaleTimeString()}`;
  return null;
}
function resolve(role, { notFamily, notModel, cheapOnly, refresh } = {}) {
  const p = loadPolicy(); const r = p.roles[roleName(role)];
  if (!r) die(`no role "${role}" in ${policyPath()}`);
  const disc = discover(refresh); const skipped = [];
  for (const name of [r.primary, ...(r.fallback || [])]) {
    const m = p.models[name];
    if (notFamily && m && m.tool === notFamily) { skipped.push(`${name}: same family (${notFamily}) as the work it checks`); continue; }
    if (notModel && name === notModel) { skipped.push(`${name}: built this task (builder ≠ reviewer)`); continue; }
    if (cheapOnly && m && m.expensive) { skipped.push(`${name}: expensive, and the budget is used`); continue; }
    const why = availability(name, p, disc);
    if (why) { skipped.push(`${name}: ${why}`); continue; }
    const flags = [];
    if (m.model) flags.push("--model", m.model);
    if (m.effort) flags.push(m.tool === "opencode" ? "--variant" : "--effort", m.effort);
    if (r.read_only) flags.push("--read-only");
    const pre = m.tool === "claude" && !process.env.ORCHESTRA_USE_API_KEY ? "env -u ANTHROPIC_API_KEY " : "";
    return { role: roleName(role), model: name, tool: m.tool, expensive: !!m.expensive, relay: relayFor(m.tool), flags, command: `${pre}node ${relayFor(m.tool)} ${flags.join(" ")}`, skipped };
  }
  return { role: roleName(role), model: null, skipped };
}

// ---------- budget ----------
const kindOf = (role) => (role.startsWith("planner") ? "planning" : role === "architecture" ? "second_opinion" : role === "final-audit" ? "final_audit" : "implementation");
const runFile = (run) => path.join(CACHE_DIR, "runs", `${run}.json`);
function spend(run, role, model, note) {
  const p = loadPolicy(); const b = p.budget || {}; const m = p.models[model];
  if (!m) die(`unknown model ${model}`);
  const led = readJSON(runFile(run), { run, calls: [] }); const kind = kindOf(roleName(role));
  const exp = led.calls.filter((c) => c.expensive); const expKind = exp.filter((c) => c.kind === kind);
  if (m.expensive) {
    if (b.expensive_calls != null && exp.length >= b.expensive_calls) return { ok: false, why: `expensive-call budget used (${exp.length}/${b.expensive_calls})` };
    const lim = b[kind]?.max_calls; if (lim != null && expKind.length >= lim) return { ok: false, why: `${kind} budget used (${expKind.length}/${lim} expensive calls)` };
  }
  led.calls.push({ role: roleName(role), model, kind, expensive: !!m.expensive, at: new Date().toISOString(), ...(note ? { note } : {}) });
  writeJSON(runFile(run), led);
  return { ok: true, why: `${kind} call recorded (${led.calls.filter((c) => c.expensive).length}/${b.expensive_calls ?? "∞"} expensive so far)` };
}

// ---------- CLI ----------
const [cmd = "roles", ...args] = process.argv.slice(2);
const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
switch (cmd) {
  case "roles": {
    const p = loadPolicy(); const disc = discover(args.includes("--refresh"));
    console.log(`Policy: ${policyPath()}\n`);
    console.log("ROLE".padEnd(17) + "CHAIN (primary → fallbacks)".padEnd(40) + "USES NOW");
    for (const [role, r] of Object.entries(p.roles)) {
      const chain = [r.primary, ...(r.fallback || [])].join(" → ");
      const res = resolve(role, {}); const now = res.model ? `${res.model}${res.model !== r.primary ? "  (fallback)" : ""}` : "NONE AVAILABLE";
      console.log(role.padEnd(17) + chain.padEnd(40) + now + (r.read_only ? "  [read-only]" : ""));
    }
    const s = readJSON(STATE, { exhausted: {} }); const ex = Object.entries(s.exhausted || {}).filter(([, u]) => new Date(u) > new Date());
    if (ex.length) console.log(`\nQuota-exhausted: ${ex.map(([t, u]) => `${t} until ${new Date(u).toLocaleTimeString()}`).join(", ")}`);
    break;
  }
  case "resolve": {
    const role = args[0] || die("usage: orchestra resolve <role> [--not-model <m>] [--not-family <tool>] [--cheap-only] [--json]");
    const r = resolve(role, { notFamily: flag("--not-family"), notModel: flag("--not-model"), cheapOnly: args.includes("--cheap-only"), refresh: args.includes("--refresh") });
    if (args.includes("--json")) { console.log(JSON.stringify(r, null, 2)); process.exit(r.model ? 0 : 1); }
    if (!r.model) { console.error(`no available model for role ${r.role}:\n  ${r.skipped.join("\n  ")}`); process.exit(1); }
    console.log(`role=${r.role} model=${r.model} tool=${r.tool}${r.expensive ? " expensive" : ""}`);
    console.log(`command=${r.command}`);
    if (r.skipped.length) console.log(`skipped=${r.skipped.join("; ")}`);
    break;
  }
  case "set": {
    const [role, primary, ...fallback] = args; if (!role || !primary) die("usage: orchestra set <role> <primary-model> [fallback-model ...] [--read-only]");
    const p = loadPolicy(); const fb = fallback.filter((a) => !a.startsWith("--"));
    for (const n of [primary, ...fb]) if (!p.models[n]) die(`unknown model "${n}". Known: ${Object.keys(p.models).join(", ")} (add one with: orchestra model <name> tool=<tool> [model=…] [effort=…])`);
    const r = roleName(role); p.roles[r] = { ...(p.roles[r] || {}), primary, fallback: fb, ...(args.includes("--read-only") ? { read_only: true } : {}) };
    savePolicy(p); console.log(`${r}: ${[primary, ...fb].join(" → ")}  (saved to ${USER_POLICY})`); break;
  }
  case "model": {
    const [name, ...kv] = args; if (!name) die("usage: orchestra model <name> tool=<tool> [model=<id>] [effort=<level>] [expensive]");
    const p = loadPolicy(); const m = { ...(p.models[name] || {}) };
    for (const a of kv) { if (a === "expensive") m.expensive = true; else { const [k, v] = a.split("="); if (!v) die(`bad option ${a}`); m[k] = v; } }
    if (!m.tool) die("tool= is required (codex, claude, agy, kimi, opencode, copilot, …)");
    p.models[name] = m; savePolicy(p); console.log(`model ${name} = ${JSON.stringify(m)}`); break;
  }
  case "exhausted": {
    const tool = args[0] || die("usage: orchestra exhausted <tool> [--until HH:MM | --for 90m]");
    let until = new Date(Date.now() + 60 * 60 * 1000);
    if (flag("--until")) { const [h, mi] = flag("--until").split(":").map(Number); until = new Date(); until.setHours(h, mi || 0, 0, 0); if (until < new Date()) until.setDate(until.getDate() + 1); }
    if (flag("--for")) { const m = /^(\d+)([mh])$/.exec(flag("--for")); if (!m) die("--for takes e.g. 90m or 2h"); until = new Date(Date.now() + Number(m[1]) * (m[2] === "h" ? 3600e3 : 60e3)); }
    const s = readJSON(STATE, { exhausted: {} }); s.exhausted = { ...(s.exhausted || {}), [tool]: until.toISOString() }; writeJSON(STATE, s);
    console.log(`${tool} marked exhausted until ${until.toLocaleString()}; roles will use their fallbacks.`); break;
  }
  case "available": {
    const tool = args[0] || die("usage: orchestra available <tool>");
    const s = readJSON(STATE, { exhausted: {} }); delete s.exhausted?.[tool]; writeJSON(STATE, s); console.log(`${tool} available again.`); break;
  }
  case "route": {
    const p = loadPolicy(); const lv = args[0];
    if (!lv) { for (const [k, v] of Object.entries(p.routing)) console.log(`${k.padEnd(8)} tasks≤${v.max_tasks ?? "any"}  planning=${v.planning}  planner=${v.planner || "–"}  second_opinion=${v.second_opinion}  reviews=${v.reviews.join(",") || "none"}  final_audit=${v.final_audit}  coordinator=${v.coordinator}`); break; }
    const name = LEVEL_ALIASES[lv] || lv; const v = p.routing[name]; if (!v) die(`unknown level ${lv} (tiny, small, feature, complex)`);
    const out = { level: name, ...v, ...(lv === "very-complex" ? { hard: true } : {}), second_opinion_only_for: p.budget?.second_opinion?.only_for || [] };
    if (args[1]) { const x = out[args[1]]; if (x === undefined) die(`no field ${args[1]}`); console.log(typeof x === "object" ? JSON.stringify(x) : String(x)); }
    else console.log(JSON.stringify(out, null, 2));
    break;
  }
  case "budget": {
    const [sub, run, role, model] = args; if (!sub || !run) die("usage: orchestra budget start|spend|show <run-id> [role model]");
    if (sub === "start") { writeJSON(runFile(run), { run, dir: flag("--dir"), started: new Date().toISOString(), calls: [] }); console.log(`budget run ${run} started: ${JSON.stringify(loadPolicy().budget)}`); }
    else if (sub === "spend") { if (!role || !model) die("usage: orchestra budget spend <run> <role> <model> [--note \"fallback from codex (quota)\"]"); const r = spend(run, role, model, flag("--note")); console.log(`${r.ok ? "OK" : "REFUSED"}: ${r.why}`); process.exit(r.ok ? 0 : 3); }
    else if (sub === "show") { const led = readJSON(runFile(run), null) || die(`no run ${run}`); const exp = led.calls.filter((c) => c.expensive); console.log(`run ${run}: ${led.calls.length} calls, ${exp.length} expensive (${exp.map((c) => `${c.model}:${c.kind}`).join(", ") || "none"})`); }
    else die(`unknown budget command ${sub}`);
    break;
  }
  case "metrics": {
    // Run metrics: the budget ledger (expensive calls, fallbacks, retries) + every relay result of the run.
    const run = args[0] || die("usage: orchestra metrics <run-id> [runs-dir]");
    const led = readJSON(runFile(run), null) || die(`no run ${run} (start one with: orchestra budget start ${run})`);
    const p = loadPolicy(); const b = p.budget || {};
    const exp = led.calls.filter((c) => c.expensive);
    const byKind = {}; for (const c of led.calls) byKind[c.kind] = (byKind[c.kind] || 0) + 1;
    console.log(`Run ${run}`);
    console.log(`  expensive calls: ${exp.length}/${b.expensive_calls ?? "∞"}  (${exp.map((c) => `${c.model}→${c.role}`).join(", ") || "none"})`);
    console.log(`  all calls by kind: ${Object.entries(byKind).map(([k, v]) => `${k} ${v}`).join(", ")}`);
    const fb = led.calls.filter((c) => c.note && /fallback/.test(c.note)); const rt = led.calls.filter((c) => c.note && /retry/.test(c.note));
    console.log(`  fallbacks: ${fb.length}${fb.length ? ` (${fb.map((c) => c.note).join("; ")})` : ""}   delta retries: ${rt.length}`);
    const dir = args[1] || led.dir;
    if (dir && fs.existsSync(dir)) {
      const results = []; const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const f = path.join(d, e.name); if (e.isDirectory()) walk(f); else if (e.name === "result.json") results.push(f); } };
      walk(dir); let tin = 0, tout = 0, usd = 0; const paid = {};
      for (const f of results) {
        const r = readJSON(f, {}); const tool = r.tool || (r.codexVersion ? "codex" : r.agyVersion ? "agy" : r.claudeVersion ? "claude" : "?");
        const u = r.usage || {}; tin += (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0); tout += u.output_tokens || 0;
        if (typeof r.total_cost_usd === "number") usd += r.total_cost_usd;
        paid[tool] = (paid[tool] || 0) + 1;
      }
      console.log(`  relay runs: ${results.length} (${Object.entries(paid).map(([t, n]) => `${t} ${n}`).join(", ")}); reported tokens in/out: ${tin.toLocaleString()}/${tout.toLocaleString()}${usd ? `; reported cost $${usd.toFixed(2)}` : ""}`);
      console.log(`  per-run detail: ~/orchestra-skills/scripts/token-report.sh ${dir}/*/run`);
    }
    break;
  }
  case "edit": { if (!fs.existsSync(USER_POLICY)) { fs.mkdirSync(CFG_DIR, { recursive: true }); fs.copyFileSync(DEFAULT_POLICY, USER_POLICY); } console.log(USER_POLICY); break; }
  case "undo": {
    const b = path.join(CFG_DIR, "backups"); const last = fs.existsSync(b) ? fs.readdirSync(b).filter((f) => f.startsWith("orchestra.")).sort().pop() : null;
    if (!last) die("nothing to undo"); fs.copyFileSync(path.join(b, last), USER_POLICY); fs.unlinkSync(path.join(b, last)); console.log(`restored ${last}`); break;
  }
  case "help": case "-h": case "--help":
    console.log(`orchestra roles [--refresh]                  role → model chains and what each uses right now
orchestra resolve <role> [--not-model <m>] [--not-family <tool>] [--cheap-only]
                                               the first available model for a role, with the relay command
orchestra set <role> <primary> [fallback…]      change a role's chain
orchestra model <name> tool=… [model=…] [effort=…] [expensive]   add/change a model alias
orchestra exhausted <tool> [--until HH:MM|--for 90m]   skip a tool while its quota is out
orchestra available <tool>                      clear that
orchestra route [level] [field]                 routing policy (tiny, small, feature, complex)
orchestra budget start <run> [--dir <runs-dir>] | spend <run> <role> <model> [--note …] | show <run>
                                               expensive-call budget for one feature (spend exits 3 when refused)
orchestra metrics <run> [runs-dir]              run metrics: expensive calls, fallbacks, retries, relay tokens
orchestra edit | undo                           your policy file / restore the previous one`); break;
  default: die(`unknown command ${cmd} (orchestra help)`);
}
