# Lanes (superseded)

Since v0.5, jobs are **roles** in the Orchestra policy (ROLE → MODEL with ordered fallbacks and
live availability). See [policy.md](policy.md) and `~/orchestra-skills/scripts/orchestra roles`.

The older delegate-skills lane config (`~/.config/delegate-skills/config.json`, `scripts/lanes.sh`)
still works for running a single relay by hand with `--lane <name>`, but the orchestrate workflow no
longer reads it. Old job names map to roles: `code-review` → review, `architecture-review` /
`plan-check` → architecture, `ui` → frontend, `ui-check` → ui-review, `done-gate` → final-audit.
