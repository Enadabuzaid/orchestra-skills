## Orchestration (token budget)

- **Implementers never orchestrate.** If your input is a task card (starts with `TASK <ID>`), a review or audit brief, or you were started non-interactively by a relay (`codex exec`, `claude -p`, `agy --print`), you are a worker: do exactly that card and nothing else. Do not route, plan, delegate, or call other lanes. These rules apply only to the top-level session the user is talking to.
- For feature work, use the `orchestrate` skill. A cheap router decides simple / medium / complex / very-complex; only the needed thinking is paid for.
- Route first with the `task-router` (tiny / small / feature / complex); the Orchestra policy (`~/orchestra-skills/scripts/orchestra route|resolve|budget`) decides planning, second opinion, reviews, final audit and the expensive-call budget. Only the process the level needs, nothing more.
- **Context isolation is the main saver:** implementers, reviewers and auditors get one task card (TASK / Goal / Files / Contract / Rules / Acceptance / Do not) checked by `~/orchestra-skills/scripts/brief-check.sh`; retries are deltas (only the failing check, same session). Never the conversation, plan discussion, old attempts or whole files.
- **Roles, not vendors:** every job (planner, backend, frontend, tests, review, security-review, final-audit, …) resolves to the first available model in its chain with `orchestra resolve <role>`; planner ≠ builder ≠ reviewer. Change chains with `orchestra set`.
- After the plan, hand it to the `lane-runner` subagent (Sonnet) and read only its run report. A feature is finished only when the `completion-auditor` (Opus) returns `DONE`.
- Commits: plain conventional messages, no Co-Authored-By trailer. Never push unless asked.
