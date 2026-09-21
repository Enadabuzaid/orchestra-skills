## Orchestration (token budget)

- Big models think, cheap models type. For any feature with more than ~2 tasks, use the `orchestrate` skill.
- Plan with Fable/Opus. Every plan must get `APPROVE` from the `plan-reviewer` subagent before any code is dispatched.
- Implementation goes to delegate-skills lanes: `complex`→codex GPT-6 Astra, `backend`→codex, `ui`→agy, `small`→claude sonnet, `fallback`→claude sonnet. Plans are made by Fable/Opus; GPT-6 Astra (`plan-check` lane) can give a second opinion. Don't write implementation code yourself when a lane fits, unless the change is tiny.
- Briefs are self-contained (paths and facts, never chat history) and forbid commits, pushes and dependency upgrades.
- After `APPROVE`, hand the plan to the `lane-runner` subagent (Sonnet): it writes the briefs, dispatches the lanes, reviews the diffs and commits. Read only its run report; don't coordinate on Opus.
- Plans must have a Definition of Done and Verify commands. A feature is finished only when the `completion-auditor` subagent (Opus) returns `DONE`. Gaps become new tasks, and the loop repeats (max 3 rounds, then escalate to the user).
- Never tell the user a feature is finished without the auditor's `DONE` and the verify results.
