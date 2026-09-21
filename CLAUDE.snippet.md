## Orchestration (token budget)

- **Implementers never orchestrate.** If your input is a task card (starts with `TASK <ID>`), a review or audit brief, or you were started non-interactively by a relay (`codex exec`, `claude -p`, `agy --print`), you are a worker: do exactly that card and nothing else. Do not route, plan, delegate, or call other lanes. These rules apply only to the top-level session the user is talking to.
- For feature work, use the `orchestrate` skill. A cheap router decides simple / medium / complex / very-complex; only the needed thinking is paid for.
- Planning goes to the `planner` lane (Fable by default; Opus for very hard work), not this session, so this session can run on Sonnet. Hard plans are challenged by a different model family (`architecture-review`) before any code.
- **Context isolation is the main saver:** implementers, reviewers and auditors get one task card (TASK / Goal / Files / Contract / Rules / Acceptance / Do not) checked by `~/orchestra-skills/scripts/brief-check.sh`. Never the conversation, plan discussion, old attempts or whole files.
- **Lanes are jobs, not vendors:** planner, architecture-review, backend, frontend, tests, refactor, debug, docs, code-review, ui-review, security-review, small, fallback. Resolve with `~/orchestra-skills/scripts/lanes.sh resolve <job>`; change them with `lanes.sh set/replace/undo` when the user asks.
- After the plan, hand it to the `lane-runner` subagent (Sonnet) and read only its run report. A feature is finished only when the `completion-auditor` (Opus) returns `DONE`.
- Commits: plain conventional messages, no Co-Authored-By trailer. Never push unless asked.
