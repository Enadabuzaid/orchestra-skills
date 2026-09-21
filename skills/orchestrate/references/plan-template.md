# Plan template

Save as `docs/plans/<YYYY-MM-DD>-<feature>.md` in the repo and commit it before any code is written.
Each task has a **role** (see `references/policy.md`): `backend`, `frontend`, `tests`, `refactor`,
`debug`, `docs`, `small`. Never name a model or vendor; the policy picks it. Mark tasks that touch auth, payments, permissions, uploads or
crypto `Sensitive: yes` so they get a security review. Medium-route plans can be short, but they
still need a Definition of Done and a Verify section.

```markdown
# Plan: <feature>

Base commit: <git rev-parse HEAD>
Planner: <model>   Run: <run id>   Route: <tiny|small|feature|complex>
Status: planning | approved | implementing | auditing | done

## Goal
<2–4 sentences: what the user can do when this is finished.>

## Current code (facts, with paths)
- <file>: <what it does today>

## Contracts shared between tasks
<Data shapes, routes, event names, and permission names that several tasks rely on. Write them
once here, so parallel implementers agree.>

## Tasks

| ID | Task | Role | Files | Depends on | Sensitive | Status |
|---|---|---|---|---|---|---|
| T1 | <one line> | backend | <paths> | – | yes/no | todo |
| T2 | <one line> | frontend | <paths> | T1 contract | no | todo |
| T3 | tests for T1/T2 edge cases | tests | <test paths> | T1, T2 | no | todo |
| T4 | README / API docs | docs | <doc paths> | T1, T2 | no | todo |

### T1: <name>
- Rules: the business rules this task enforces (short bullets).
- Acceptance: named test cases.
- Task gate: <the command that checks only this task, e.g. one test file>.
(These become the task card, so write only what a builder needs.)

### T2: …

## Definition of Done
- [ ] <user-visible outcome 1>
- [ ] <user-visible outcome 2>
- [ ] Full test suite, static analysis, formatter and build all pass
- [ ] No debug leftovers, no TODOs added, nothing uncommitted

## Verify
| Check | Command | Who |
|---|---|---|
| Tests | `<full test command>` | auditor |
| Static analysis | `<cmd>` | auditor |
| Format | `<cmd --test>` | auditor |
| Build | `<cmd>` | auditor |
| Runtime | `<curl / artisan / script that exercises the feature>` | auditor |
| UI | <what to click and what you should see> | manual |

## Out of scope
- <things this plan deliberately does not change>

## Gap log
<The completion loop adds G1, G2, … rows to the task table and notes here what the auditor found.>
```
