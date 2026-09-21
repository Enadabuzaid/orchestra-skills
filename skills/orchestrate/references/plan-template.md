# Plan template

Save as `docs/plans/<YYYY-MM-DD>-<feature>.md` in the repo and commit it before any code is written.

```markdown
# Plan: <feature>

Base commit: <git rev-parse HEAD>
Status: planning | approved | implementing | auditing | done

## Goal
<2–4 sentences: what the user can do when this is finished.>

## Current code (facts, with paths)
- <file>: <what it does today>

## Contracts shared between tasks
<Data shapes, routes, event names, and permission names that several tasks rely on. Write them
once here, so parallel implementers agree.>

## Tasks

| ID | Task | Lane | Files | Depends on | Status |
|---|---|---|---|---|---|
| T1 | <one line> | backend | <paths> | – | todo |
| T2 | <one line> | ui | <paths> | T1 contract | todo |

### T1: <name>
- What to build, precisely.
- Acceptance tests (names or cases).
- Task gate: <the command that checks only this task, e.g. one test file>.

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
