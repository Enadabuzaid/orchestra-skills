# The Orchestra policy

One file decides who does what, how much process each request gets, and how many expensive calls a
feature may make: `~/.config/orchestra-skills/orchestra.json`. Run `orchestra edit` to create your
copy from `examples/orchestra.json`.

## ROLE → MODEL (not model → role)

Orchestra asks "I need a backend builder", and the policy answers with the first **available**
model in that role's chain:

```
backend:  codex → kimi → deepseek → sonnet
          Codex available?          → Codex
          Codex quota exhausted?    → Kimi
          Kimi not installed?       → DeepSeek
          DeepSeek unavailable?     → Sonnet
```

"Available" means the relay skill is installed, the CLI is installed and logged in, the model is one
the CLI offers, and the tool isn't marked quota-exhausted (`orchestra exhausted codex --until 21:34`,
set automatically when a relay fails with a quota error).

`models` gives each name a tool and settings (`astra` = codex + gpt-6-astra + high effort,
`expensive: true`). `roles` gives each job a `primary`, an ordered `fallback` list, and flags:

| Flag | Meaning |
|---|---|
| `read_only` | the role never writes: planners, reviews, audits. Their fallbacks stay read-only too |
| `different_from_builder` | a review must not use the model that built the task (`--not-model`) |
| `different_family_from_planner` | the second opinion must come from another model family (`--not-family`) |

Default roles (thinking on strong models, typing on the cheapest available one; Planner ≠ Builder ≠
Reviewer). `opencode-free` is OpenCode Zen's free tier: $0, the last stop before Sonnet.

| Group | Role | Chain |
|---|---|---|
| Planning | `planner-light` | sonnet → luna → copilot → haiku |
| | `planner` | **fable** → astra → opus |
| | `planner-hard` | **opus** → fable → astra |
| | `architecture` (second opinion) | **astra** → opus (a different family from the planner) |
| Building | `backend` | **codex** → kimi → deepseek → luna → opencode-free → sonnet |
| | `frontend` | **antigravity** → codex → kimi → luna → opencode-free → sonnet |
| | `tests` | **kimi** → deepseek → luna → antigravity → opencode-free → sonnet |
| | `refactor` | **kimi** → codex → luna → opencode-free → sonnet |
| | `debug` | codex → luna → opencode-free → sonnet |
| | `docs`, `small` | **deepseek** → … → opencode-free → sonnet |
| Review (read-only) | `review` (every task) | **deepseek** → luna → opencode-free → copilot → haiku → sonnet |
| | `ui-review` | **codex** → luna → copilot → sonnet |
| | `security-review` | **astra** → copilot → sonnet |
| Final | `final-audit` | **opus** |

Rules the engine enforces (`orchestra check`, and at resolve time): Haiku never builds; Copilot only
reviews (`read_only_tool`: headless writes need `--allow-all-tools`); a read-only role never lands on
a relay without `--read-only` (Kimi's), and flags a relay doesn't accept (`--effort` for Kimi) are
not passed. A failed CLI discovery is never cached: the last good result, then a PATH check, is used.

Older names still resolve: `code-review` → review, `architecture-review`/`plan-check` →
architecture, `ui` → frontend, `ui-check` → ui-review, `done-gate` → final-audit.

## Routing levels

| Level | Tasks | Planning | 2nd opinion | Reviews | Final audit | Who coordinates |
|---|---|---|---|---|---|---|
| tiny | 1 | none | no | none | no | the session |
| small | ≤2 | light (`planner-light`) | no | review | no | the session |
| feature | ≤6 | full (`planner`) | no | review, ui-review, security-review | yes | `lane-runner` |
| complex | any | advanced (`planner` / `planner-hard`) | **yes, if justified** | all | yes | `lane-runner` |

## Budget (per feature run)

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

- A **normal feature spends 2 expensive calls**: Fable plans once, Opus audits once.
- A **complex feature** spends 3: plus one Astra second opinion, and only when the work touches
  architecture, security, payments or migrations (or the router said `Hard: yes`).
- `orchestra budget spend` records each call **before** it's made and exits 3 when the budget
  refuses. The orchestrator then uses `orchestra resolve <role> --cheap-only`, or skips the optional
  step, and says so.
- Cheap calls (Sonnet, Haiku, Luna, Codex default, Antigravity, Kimi, DeepSeek) are recorded for
  metrics, but they don't count against the expensive budget.
- Revising a plan after a second opinion does **not** call the expensive planner again. The fixes
  are applied by the orchestrator or `planner-light`.
