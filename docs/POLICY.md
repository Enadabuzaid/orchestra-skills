# The Orchestra policy: roles, routing, budget

Orchestra is an AI engineering router: it decides **how much intelligence, context and money a
coding task deserves**. Everything it decides comes from one file you control:

```bash
orchestra edit        # creates ~/.config/orchestra-skills/orchestra.json from the default, prints its path
orchestra roles       # what each role uses right now
```

(`orchestra` is installed to `~/.local/bin`. Otherwise use `~/orchestra-skills/scripts/orchestra`.)

## 1. Routing: how much process a request gets

A cheap Haiku router classifies every request **before** any expensive call:

| Level | Example | What happens |
|---|---|---|
| **tiny** | "change the Log in button text" | one card → builder → test → commit. No plan, no reviewer, no audit |
| **small** | "add a notes field to the contact form" | light plan (Sonnet) → ≤2 cards → builders → review → Verify. No final audit |
| **feature** | "a My Visits page with endpoint, tests, docs" | **Fable** plans → builders → reviewers → Verify → **Opus** final audit |
| **complex** | auth, payments, migrations, new subsystems | Fable plans (Opus if Hard) → **Astra** second opinion (only for architecture/security/payments/migrations) → builders → reviewers → Verify → Opus audit |

See or change it: `orchestra route`, and the `routing` section of your policy file.

## 2. Roles: ROLE → MODEL, with fallbacks

Orchestra asks for a **role** ("I need a backend builder"), and the policy returns the first model
in that role's chain that is **available right now**: installed, logged in, offers that model, and
not out of quota.

```bash
orchestra roles                                   # every role, its chain, and what it uses now
orchestra resolve backend                         # the model + exact command for one role
orchestra set backend codex kimi deepseek sonnet  # primary, then fallbacks in order
orchestra set tests kimi deepseek luna sonnet
orchestra set review kimi deepseek haiku --read-only
orchestra undo                                    # previous policy
```

Default roles: **thinking on strong models, typing on the cheapest available one**, and
Planner ≠ Builder ≠ Reviewer.

| | Role | Chain |
|---|---|---|
| **Planning** | planner-light (small) | Sonnet → Luna → Copilot → Haiku |
| | planner (feature) | Fable → Astra → Opus |
| | planner-hard (complex, Hard) | Opus → Fable → Astra |
| | architecture (second opinion) | Astra → Opus, always a different family from the planner |
| **Building** | backend | Codex → Kimi → DeepSeek → Luna → OpenCode free → Sonnet |
| | frontend | Antigravity → Codex → Kimi → Luna → OpenCode free → Sonnet |
| | tests | Kimi → DeepSeek → Luna → Antigravity → OpenCode free → Sonnet |
| | refactor | Kimi → Codex → Luna → OpenCode free → Sonnet |
| | debug | Codex → Luna → OpenCode free → Sonnet |
| | docs, small | DeepSeek → … → OpenCode free → Sonnet |
| **Review** (read-only) | review | DeepSeek → Luna → OpenCode free → Copilot → Haiku → Sonnet, never the builder's model |
| | ui-review | Codex → Luna → Copilot → Sonnet |
| | security-review | Astra → Copilot → Sonnet |
| **Final** | final-audit | Opus |

Why the chains look like this (all from recorded runs, see [TESTING.md](TESTING.md)):

- **Other subscriptions first, Sonnet last.** Codex and Luna run on ChatGPT, Antigravity on Google,
  Kimi and DeepSeek on their own plans, and `opencode-free` (OpenCode Zen's free tier,
  `opencode/big-pickle`) costs nothing. Sonnet is the reliable last stop, on your Claude plan.
- **Haiku never builds.** As the `docs` builder it looped for 21 turns and 650k tokens on a README
  (v0.5 end-to-end run). It stays in read-only chains only.
- **Copilot only reviews.** Headless Copilot can write only with `--allow-all-tools` (full access),
  so its model is marked `read_only_tool` and `orchestra check` refuses it in a writing role.
- **Kimi builds but never reviews.** Its relay has no `--read-only`, so the engine skips it for
  read-only roles (planners, reviews, audit), and says so.

Models are named in the `models` section (`astra` = Codex + gpt-6-astra, high effort, expensive).
Add one with `orchestra model <name> tool=<tool> model=<id> effort=<level> [expensive]`, then run
`orchestra check`: it verifies every chain names a known model, read-only roles use only relays
that can enforce read-only, and writing roles never use a read-only-only tool.

### Availability

`orchestra roles` asks delegate-setup's discovery which CLIs are installed, logged in, and which
models they offer, and caches the answer for 15 minutes. A failed or empty probe is **never** cached:
the engine keeps the last good result, and without one falls back to a PATH check, so a hiccup can't
make every role `NONE AVAILABLE` (that happened once, for 15 minutes, in the v0.5 end-to-end run).
`orchestra roles --refresh` re-probes; `doctor.sh` always does.

### Quota

When a tool fails with a quota error, the orchestrator runs `orchestra exhausted <tool> --until
<reset time>`, and every role skips that tool until then. You can do it by hand too:

```bash
orchestra exhausted codex --until 21:34
orchestra available codex
```

## 3. Budget: expensive calls per feature

```json
"budget": {
  "expensive_calls": 3,
  "planning":       { "max_calls": 1 },
  "second_opinion": { "max_calls": 1, "only_for": ["architecture", "security", "payments", "migrations"] },
  "final_audit":    { "max_calls": 1 },
  "implementation": { "max_retries": 2, "retry_mode": "delta" },
  "briefs":         { "max_tokens": 1500 },
  "reviews":        { "max_tokens": 1000 }
}
```

- **A normal feature makes 2 expensive calls: Fable once, Opus once.** A complex one makes at most 3.
- Every call is recorded **before** it's made (`orchestra budget spend`). A call over budget is
  refused, and Orchestra uses a cheap model for that step (or skips an optional step) and tells you.
- Plans aren't re-written by the expensive planner after a second opinion. The fixes are applied cheaply.
- `briefs.max_tokens` and `reviews.max_tokens` are enforced by `brief-check.sh` on every card.

## 4. Minimum sufficient context

Builders get a card like this, and nothing else:

```
T2 — Cancel Booking Action
Files:       app/Actions/CancelBooking.php, tests/Feature/CancelBookingTest.php
Contract:    Booking statuses: pending | confirmed | cancelled | completed
Rules:       patient owns booking · >24h before visit · already-cancelled is idempotent
Acceptance:  owner can cancel · other patient 403 · <24h fails · tests pass
Don't:       modify migrations/payment code · commit · change dependencies · orchestrate
```

A failed check doesn't resend the card. It gets a **delta retry** in the same session:

```
Continue T2.
Only failing check: CancelBookingTest > another patient gets 403 (expected 403, actual 404)
Investigate and fix this only.
Already accepted: ✓ cancellation works ✓ status changes ✓ owner case passes
```

Formats: `skills/orchestrate/references/brief-template.md`.

## 5. Run metrics

Every feature run gets an id. The final report includes:

```bash
orchestra metrics <run>
#  expensive calls: 2/3  (fable→planner, opus→final-audit)
#  fallbacks: 1 (fallback from codex (quota))   delta retries: 1
#  relay runs: 9 (codex 4, agy 2, claude 3); reported tokens in/out: …
```
