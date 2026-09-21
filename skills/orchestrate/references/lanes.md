# Lanes: jobs, not vendors

A lane names a **job**. Which tool and model does that job lives only in the user's lane config
(`~/.config/delegate-skills/config.json`, edited with `lanes.sh`). The workflow never names a
vendor, so remapping a lane changes nothing else.

Resolve a job to its configured lane with:

```bash
~/orchestra-skills/scripts/lanes.sh resolve <job>      # prints: lane=<name> tool=<tool> model=<model>
```

It also accepts the older names listed below, so existing configs keep working.

## The jobs

| Job lane | Used for | Writes? |
|---|---|---|
| `planner` | writes the plan (normal and complex work) | read-only |
| `planner-hard` | writes the plan for very-complex work | read-only |
| `planner-fallback`, `planner-alt` | next planners to try when the one before fails (quota, availability) | read-only |
| `architecture-review` | challenges a plan: **must be a different model family from the planner** | read-only |
| `architecture-review-alt` | the challenger when `architecture-review` is the same family as the planner | read-only |
| `backend` | server code: actions, models, routes, jobs, migrations | writes |
| `frontend` | pages, components, styling | writes |
| `tests` | writing or extending tests | writes |
| `refactor` | behaviour-preserving restructuring | writes |
| `debug` | diagnosing a failing gate: gets the failure output and fixes the cause | writes |
| `docs` | README, API docs, changelog | writes |
| `code-review` | cheap line-by-line review of **every** task's diff | read-only |
| `ui-review` | extra review of **frontend** diffs (states, accessibility, UX regressions) | read-only |
| `security-review` | extra review of **sensitive** diffs: auth, permissions, payments, uploads, raw SQL, crypto, secrets | read-only |
| `final-audit` | the DONE/GAPS decision in `orchestrate-portable` (Claude Code uses the `completion-auditor` agent) | read-only |
| `small` | one-card quick fixes (the simple route) | writes |
| `fallback` | the last resort when a lane (and its `-fallback`) fails | writes |

Optional: any `<job>-fallback` lane is tried before the global `fallback` for that job.

## Older names (still accepted)

| Old name | Job |
|---|---|
| `ui` | `frontend` |
| `review` | `code-review` |
| `ui-check` (any `<lane>-check`) | `ui-review` (a review of that lane's diffs) |
| `plan-check` | `architecture-review` |
| `plan-gate` | `architecture-review-alt` |
| `done-gate` | `final-audit` |
| `complex` | hard implementation work. Prefer `backend`/`refactor` with a strong model mapped to them |

## Rules the workflow follows

1. **The planner picks each task's job lane** from this list. The router's `Lanes:` hint uses the
   same names.
2. **Reviews after each task, in this order:** `code-review` (every task) → `ui-review` (frontend
   tasks) → `security-review` (sensitive tasks: when the plan marks the task `Sensitive: yes`, or its
   files touch auth, permissions, payments, uploads or crypto). A review lane that isn't configured is
   skipped, and the `lane-runner` then reviews the diff itself.
3. **A failing task gate** after the implementer's own retry goes to `debug` (if configured) with
   the failing output, before trying `fallback`.
4. **Challenger family rule:** the architecture review must come from a different model family
   than the planner that actually ran. Use `architecture-review`, unless it's the same family, in which
   case use `architecture-review-alt`.
5. **Read-only stays read-only.** Planner, review, architecture-review and final-audit jobs always
   run with `--read-only`, and so does any fallback that stands in for them, even if that lane
   can normally write.
6. **Fallback chain for any job:** `<job>` → `<job>-fallback` → `fallback`. For planners:
   `planner` → `planner-fallback` → `planner-alt`. Always report which lane actually ran.
