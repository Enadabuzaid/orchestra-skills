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

## The ideas (v0.5 Token Intelligence)

1. **Route before anything expensive.** Tiny work never meets a planner, a reviewer or Opus.
2. **ROLE → MODEL, not model → role.** Orchestra asks for a backend builder; the policy answers with
   the first available model in that role's chain (`docs/POLICY.md`).
3. **A token budget per feature.** A normal feature = Fable once + Opus once. Every expensive call is
   recorded before it's made and refused when over budget.
4. **Minimum sufficient context.** One short card per builder/reviewer, delta retries, never the
   conversation.
5. **Planner ≠ Builder ≠ Reviewer.** Reviews come from a different model than the builder; second
   opinions from a different family than the planner.

## Where each rule lives

| What | File |
|---|---|
| Routing rubric | `agents/task-router.md` |
| Workflow (Claude Code) | `skills/orchestrate/SKILL.md` |
| Workflow (Codex / other apps) | `skills/orchestrate-portable/SKILL.md` |
| Roles, routing, budget | `examples/orchestra.json`, `skills/orchestrate/references/policy.md`, `scripts/orchestra` |
| Task card format | `skills/orchestrate/references/brief-template.md` |
| Plan format | `skills/orchestrate/references/plan-template.md` |
| Build coordinator | `agents/lane-runner.md` |
| Architecture review instructions | `agents/plan-reviewer.md` |
| Final audit instructions | `agents/completion-auditor.md` |
