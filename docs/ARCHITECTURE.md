# Architecture

```
                         ┌─────────────────┐
                         │  USER REQUEST   │
                         └────────┬────────┘
                                  ▼
                         ┌─────────────────┐
                         │   TASK ROUTER   │  Haiku: a few quick looks at the code
                         └────────┬────────┘
     ┌──────────────┬─────────────┼─────────────────┬────────────────────┐
     ▼              ▼             ▼                 ▼                    │
  simple         medium        complex         very-complex              │
  (no plan)         │             │                 │                    │
     │              ▼             ▼                 ▼                    │
     │         ┌─────────────────────────────────────────┐              │
     │         │ PLANNER lane  (one planner, read-only)  │              │
     │         │ planner → Fable     planner-hard → Opus │              │
     │         │ fallback → Opus     alt → GPT-6 Astra   │              │
     │         └───────────┬─────────────────────────────┘              │
     │                     │ plan file (tasks, contracts, DoD, Verify)   │
     │              medium │   complex / very-complex                    │
     │                     ▼                                             │
     │         ┌─────────────────────────────────────────┐              │
     │         │ ARCHITECTURE REVIEW (different family)  │              │
     │         │ Claude planned → Astra; else → Fable     │              │
     │         └───────────┬─────────────────────────────┘              │
     │                     │ APPROVE                                     │
     ▼                     ▼                                             │
┌──────────────────────────────────────────────────────────────────┐    │
│ LANE-RUNNER (Sonnet): one TASK CARD per task (context isolation)  │    │
│                                                                    │    │
│  backend   frontend   tests   refactor   debug   docs   small      │    │
│     └────────┴────────┴───────┴─────────┴───────┴──────┘          │    │
│  each task → code-review → ui-review (frontend) → security-review  │    │
│  (sensitive) → task gate → one commit                              │    │
└──────────────────────────────────┬─────────────────────────────────┘    │
                                   ▼                                      │
                    ┌──────────────────────────────┐                     │
                    │ FINAL AUDIT (Opus), once      │  GAPS → fix tasks ──┘
                    │ checklist + Verify commands   │  (max 3 rounds)
                    └──────────────┬───────────────┘
                                   ▼ DONE
                               report to you
```

## The three ideas

### 1. Context isolation (the biggest saver)

An implementer never sees the conversation, the architecture discussion, old attempts, your general
preferences, the whole README or the whole project. It receives **one task card**:

```
TASK T3
You are the implementer for this one task. Do it directly; do not plan, orchestrate or delegate.

Goal:        A patient can cancel their own booking.
Files:       app/Actions/CancelBooking.php, app/Models/Booking.php, tests/Feature/BookingCancellationTest.php
Contract:    POST /bookings/{booking}/cancel
Rules:       owner only · not < 24h before the visit · status → cancelled
Acceptance:  owner can cancel · other user 403 · < 24h rejected · test passes
Do not:      commit · change dependencies · touch other files · orchestrate · modify payments/migrations
```

`scripts/brief-check.sh` enforces this: every section must be present, the card must be under 450
words, and it's rejected if it shows signs of leaked context ("as we discussed", "the previous
attempt failed", "option A vs B", pasted file contents). Reviewers get the same treatment: a card
plus the saved diff, never the history.

The "you are the implementer" line exists for a reason. Implementers run the same CLIs as
orchestrators and load the same global rules, and in testing a Codex worker started orchestrating
its own small task until the card told it not to.

### 2. Lanes are jobs, not vendors

`planner`, `architecture-review`, `backend`, `frontend`, `tests`, `refactor`, `debug`, `docs`,
`code-review`, `ui-review`, `security-review`, `final-audit`, `small`, `fallback`.

The workflow only ever says "send this to `backend`". Which tool and model that means lives in your
lane config. Remap it any time without touching the workflow:

```bash
lanes set backend kimi          # tomorrow
lanes set tests opencode model=deepseek/deepseek-chat
lanes set frontend codex
```

The full list and rules are in `skills/orchestrate/references/lanes.md`.

### 3. Pay for thinking only where it's needed

| Route | Planner | Architecture review | Final audit |
|---|---|---|---|
| simple | none | none | none: the task gate decides |
| medium | Fable | none | Opus, once |
| complex | Fable | Astra (a different family) | Opus, once |
| very-complex | Opus | Astra | Opus, once |

Because planning runs in the `planner` lane, **your main session can run on Sonnet.** The expensive
models are called for exactly those steps.

## Where each rule lives

| What | File |
|---|---|
| Routing rubric | `agents/task-router.md` |
| Workflow (Claude Code) | `skills/orchestrate/SKILL.md` |
| Workflow (Codex / other apps) | `skills/orchestrate-portable/SKILL.md` |
| Job lanes, old names, review/debug/fallback rules | `skills/orchestrate/references/lanes.md` |
| Task card format | `skills/orchestrate/references/brief-template.md` |
| Plan format | `skills/orchestrate/references/plan-template.md` |
| Build coordinator | `agents/lane-runner.md` |
| Architecture review instructions | `agents/plan-reviewer.md` |
| Final audit instructions | `agents/completion-auditor.md` |
