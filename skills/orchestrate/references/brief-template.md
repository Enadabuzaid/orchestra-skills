# Brief template

Copy, fill, save as `brief-<task>.md` in the scratchpad (not in the repo).

```markdown
# Task: <one line>

## Goal
<2–4 sentences: what must be true when done.>

## Context (facts only)
- Repo: <path>. Stack: <e.g. Laravel 12, Inertia React, Pest>.
- Relevant files: <paths, with one line each on why>.
- Patterns to copy: <path of an existing similar file>.

## Do
1. <step>
2. <step>

## Acceptance
- <test file / test name that must pass>
- Gates: `<test cmd>`, `<static analysis cmd>`, `<formatter cmd>`

## Do NOT
- Commit, push, or create branches.
- Run `composer update`, `npm update`, or any dependency upgrade.
- Touch files outside: <allowed paths>.
- Run migrations against a non-test database.

## Report back
Files changed, gates run with their output, anything you were unsure about.
```
