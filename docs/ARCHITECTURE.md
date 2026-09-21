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
   tiny           small        feature          complex                  │
  (no plan)   (light plan,        │                 │                    │
     │         Sonnet)            ▼                 ▼                    │
     │              │    ┌─────────────────────────────────────────┐    │
     │              │    │ PLANNER role (read-only, 1 expensive)   │    │
     │              │    │ planner → Fable → Astra → Opus          │    │
     │              │    │ planner-hard (Hard: yes) → Opus → …     │    │
     │              │    └───────────┬─────────────────────────────┘    │
     │              │                │ plan file (tasks, contracts, DoD, Verify)
     │              │        feature │   complex, if architecture/security/payments/migrations
     │              │                ▼                                   │
     │              │    ┌─────────────────────────────────────────┐    │
     │              │    │ SECOND OPINION (different family)       │    │
     │              │    │ architecture → Astra → Opus             │    │
     │              │    └───────────┬─────────────────────────────┘    │
     │              │                │ APPROVE (fixes applied cheaply)   │
     ▼              ▼                ▼                                   │
┌──────────────────────────────────────────────────────────────────┐    │
│ BUILD (session for tiny/small; LANE-RUNNER on Sonnet otherwise)   │    │
│ one TASK CARD per task (context isolation, brief-check.sh)        │    │
│                                                                    │    │
│  role → orchestra resolve → first AVAILABLE model in its chain     │    │
│  backend   frontend   tests   refactor   debug   docs   small      │    │
│  (Codex, Antigravity, Kimi, DeepSeek, Luna, OpenCode free, Sonnet) │    │
│                                                                    │    │
│  gate → delta retry (same session, only the failing check)         │    │
│  → review by a DIFFERENT model (+ ui-review, security-review)      │    │
│  → one commit per task                                             │    │
└──────────────────────────────────┬─────────────────────────────────┘    │
                                   ▼  (feature, complex)                  │
                    ┌──────────────────────────────┐                     │
                    │ FINAL AUDIT (Opus), once      │  GAPS → fix tasks ──┘
                    │ checklist + Verify commands   │  (re-verified cheaply)
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
