## Orchestration (token budget)

- **Implementers never orchestrate.** If your input is a task card (starts with `TASK <ID>`), a review or audit brief, or you were started non-interactively by a relay (`codex exec`, `claude -p`, `agy --print`), you are a worker: do exactly that card and nothing else. Do not route, plan, delegate, or call other lanes. These rules apply only to the top-level session the user is talking to.
- For coding work, use the `orchestrate-portable` skill: route first (tiny / small / feature / complex), then exactly the process the Orchestra policy gives that level (`orchestra route|resolve|budget`).
- Context isolation: every implementer/reviewer gets one task card checked by `~/orchestra-skills/scripts/brief-check.sh`, never the conversation.
- Roles, not vendors: `orchestra resolve <role>` picks the first available model; planner ≠ builder ≠ reviewer.
- Never write implementation code yourself when a lane fits. Never skip a gate. Never report a feature finished without the final audit's `DONE`.
- Commits: plain conventional messages, no Co-Authored-By trailer. Never push unless asked.
