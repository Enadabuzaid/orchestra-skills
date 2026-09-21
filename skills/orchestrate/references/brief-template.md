# The task card (brief)

**Context isolation is the core of orchestra.** Most of the token savings come from implementers
seeing only their task, not from picking a cheaper model. An implementer receives **one task card**
and nothing else.

## Never put in a card

- the conversation, or any summary of it
- architecture discussion, alternatives considered, or old attempts
- the user's general preferences (only the rules that apply to *this* task)
- whole files, the whole README, or the whole plan (only the facts this task needs)
- other tasks' details (only the **contract** this task depends on or provides)

## Format (copy it exactly)

```markdown
TASK <ID>
You are the implementer for this one task. Do it directly; do not plan, orchestrate or delegate.

Goal:
<one or two sentences: what is true when this task is done>

Files:
<path>            ← only these may be created or changed
<path>

Contract:
<the interface this task provides or consumes: route, signature, event, data shape>

Rules:
- <business rule>
- <business rule>

Acceptance:
- <observable check, usually a named test case>
- <task gate command> passes

Do not:
- commit, push, or create branches
- install, update or remove dependencies
- change files outside Files
- orchestrate, delegate, or start other agents
- <task-specific: e.g. modify payment code, modify migrations>
```

## Example

```markdown
TASK T3
You are the implementer for this one task. Do it directly; do not plan, orchestrate or delegate.

Goal:
A patient can cancel their own booking.

Files:
app/Actions/CancelBooking.php
app/Models/Booking.php
tests/Feature/BookingCancellationTest.php

Contract:
POST /bookings/{booking}/cancel → 302 back with status "cancelled"

Rules:
- only the user who owns the booking may cancel it
- cannot cancel less than 24h before the appointment
- status becomes cancelled

Acceptance:
- owner can cancel
- another user gets 403
- less than 24h before the appointment is rejected
- php artisan test --compact tests/Feature/BookingCancellationTest.php passes

Do not:
- commit, push, or create branches
- install, update or remove dependencies
- change files outside Files
- orchestrate, delegate, or start other agents
- modify payment code or migrations
```

Why the second line and the "orchestrate" rule: implementers run the same CLIs as orchestrators, and
those CLIs load the user's global rules (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`). Without an
explicit "you are the implementer", a worker can start orchestrating its own small task (this was
observed in testing).

## Limits

- **At most 450 words** (about one page). If a task needs more, it's two tasks.
- Every section is required. `Contract:` may say `none` for self-contained tasks.
- Check it before sending: `~/orchestra-skills/scripts/brief-check.sh <card.md>`

Delta briefs (follow-ups to the same session) are shorter: `TASK <ID> (round N)`, then only what to
change and why, then the same `Do not:` block.
