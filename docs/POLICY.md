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

Default roles: **Planner ≠ Builder ≠ Reviewer**.

| | Role | Chain |
|---|---|---|
| **Planning** | planner | Fable → Astra → Opus |
| | planner-hard | Opus → Fable → Astra |
| | architecture (second opinion) | Astra → Opus, always a different family from the planner |
| **Building** | backend | Codex → Kimi → DeepSeek → Sonnet |
| | frontend | Antigravity → Codex → Kimi → Sonnet |
| | tests | Kimi → DeepSeek → Luna → Sonnet |
| | refactor | Kimi → Codex → Sonnet |
| | small, docs | DeepSeek → … → Sonnet |
| **Review** | review | Kimi → DeepSeek → Luna → Haiku → Sonnet, never the builder's model |
| | ui-review | Codex (read-only) → Luna → Sonnet |
| | security-review | Astra → Sonnet |
| **Final** | final-audit | Opus |

Models are named in the `models` section (`astra` = Codex + gpt-6-astra, high effort, expensive).
Add one with `orchestra model <name> tool=<tool> model=<id> effort=<level> [expensive]`.

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
