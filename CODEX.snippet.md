## Orchestration (token budget)

- For any feature with more than ~2 tasks, use the `orchestrate-portable` skill: you plan (on your
  current model, e.g. gpt-6-astra), Claude approves the plan through the read-only `plan-gate` lane,
  the delegate-skills lanes build (`backend`, `ui`, …), and Claude's read-only `done-gate` decides DONE.
- Never write implementation code yourself when a lane fits. Never skip a gate. Never report a
  feature finished without the done-gate's `DONE`.
- Lanes are in `~/.config/delegate-skills/config.json`; change them with `~/orchestra-skills/scripts/lanes.sh`.
- Commits: plain conventional messages, no Co-Authored-By trailer. Never push.
