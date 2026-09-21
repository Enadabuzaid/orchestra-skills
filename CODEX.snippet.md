## Orchestration (token budget)

- **Implementers never orchestrate.** If your input is a task card (starts with `TASK <ID>` or `<ID> — <title>`), a delta retry (`Continue <ID>.`), a review or audit brief, or you were started non-interactively by a relay (`codex exec`, `claude -p`, `agy --print`, `opencode run`, `kimi`), you are a worker: do exactly that card and nothing else. Do not route, plan, delegate, or call other roles. These rules apply only to the top-level session the user is talking to.
- For coding work in any project, use the `orchestrate-portable` skill: route first (tiny / small / feature / complex), then exactly the process the Orchestra policy gives that level (`orchestra route|resolve|budget`, in `~/.local/bin` or `~/orchestra-skills/scripts/orchestra`).
- Thinking on strong models (Fable / Opus / Astra, budgeted), typing on the cheapest available one: `orchestra resolve <role>` picks the first available model in the role's chain; planner ≠ builder ≠ reviewer.
- Context isolation: every implementer/reviewer gets one task card checked by `~/orchestra-skills/scripts/brief-check.sh`, never the conversation. Retries are deltas.
- Never write implementation code yourself when a role fits. Never skip a gate. Never report a feature finished without the final audit's `DONE`.
- Commits: plain conventional messages, no Co-Authored-By trailer. Never push unless asked.
