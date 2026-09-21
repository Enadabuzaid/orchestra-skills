## Orchestration (token budget)

- Big models think, cheap models type. For any feature with more than ~2 tasks, use the `orchestrate` skill.
- Plan with Fable/Opus. Every plan must get `APPROVE` from the `plan-reviewer` subagent before any code is dispatched.
- Implementation goes to delegate-skills lanes: `backend`→codex, `ui`→agy, `small`→claude sonnet, `fallback`→copilot. Don't write implementation code yourself when a lane fits, unless the change is tiny.
- Briefs are self-contained (paths and facts, never chat history) and forbid commits, pushes and dependency upgrades.
- Per-task review goes to the `diff-reviewer` subagent (Sonnet). Read only its summary and the flagged hunks, then re-run the gates and commit yourself.
- One final Opus audit per feature.
