# Cards: minimum sufficient context

**Orchestra's strongest rule: give each model the minimum sufficient context.** Most of the token
savings come from here, not from picking a cheaper model. A builder, reviewer or debugger receives
**one short card** and nothing else.

Never put in a card:
- the conversation, or a summary of it
- business history, architecture discussion, alternatives, or old attempts
- the full plan, the whole README, unrelated services, or file contents (give paths)
- other tasks' details (only the contract this task relies on or provides)

Check every card before sending: `~/orchestra-skills/scripts/brief-check.sh <card.md>`. Size limits
come from the policy budget (`briefs.max_tokens`, `reviews.max_tokens`). Aim for well under them;
most cards are 100–250 words.

## 1. Task card (builders)

```markdown
T2 — Cancel Booking Action

Files:
- app/Actions/CancelBooking.php
- tests/Feature/CancelBookingTest.php

Contract:
Booking statuses: pending | confirmed | cancelled | completed

Rules:
- patient owns booking
- cancellation allowed >24h before visit
- already-cancelled booking is idempotent

Acceptance:
- owner can cancel
- another patient gets 403
- <24 hours fails
- php artisan test --compact tests/Feature/CancelBookingTest.php passes

Don't:
- modify migrations or payment code
- commit, or change dependencies
- orchestrate or delegate (you are the builder for this one task)
```

- **Header:** `<ID> — <title>`. The title is the goal.
- **Required:** Files, Acceptance, Don't. **Rules** or **Contract** when there are any (usually both).
- **Don't** always forbids committing, dependency changes, and orchestrating/delegating. Workers run
  the same CLIs as orchestrators and load the same global rules, and in testing a worker started
  orchestrating its own task until the card told it not to.

## 2. Delta retry (same session, only what failed)

When a task gate or a review fails, **don't resend the card.** Continue the same implementer
session (`--session <id>` from its `result.json`) with only this:

```markdown
Continue T2.

Only failing check:
CancelBookingTest > another patient gets 403
Expected: 403
Actual: 404

Investigate and fix this only.

Already accepted:
✓ cancellation works
✓ status changes
✓ owner case passes

Don't: commit, change dependencies, or touch files outside T2.
```

- **Required:** `Continue <ID>.`, a failing check with expected/actual (or the reviewer's numbered
  finding with file:line), `Already accepted:` and `Don't:`.
- The limit is a third of `briefs.max_tokens`. Paste the failing assertion, not the whole test log.
- After `implementation.max_retries` delta retries, stop retrying: send one delta to the `debug`
  role, then move to the role's next fallback model.

## 3. Review card (reviewers, read-only)

```markdown
Review T2 — Cancel Booking Action

Diff: /tmp/orchestrate/<repo>/T2/review/diff.patch

Check against:
- Rules: patient owns booking; >24h only; idempotent when already cancelled
- Acceptance: owner cancels; other patient 403; <24h fails
- Allowed files: app/Actions/CancelBooking.php, tests/Feature/CancelBookingTest.php

Reply: PASS, or numbered findings with file:line (bugs, missing cases, security, scope).
Don't: edit anything.
```

- The reviewer must be a **different model from the builder** (`orchestra resolve review
  --not-model <builder>`). For security and architecture reviews, prefer a different family
  (`--not-family <builder tool>`).
- The limit is `reviews.max_tokens`. The diff is a file path, never pasted in.
