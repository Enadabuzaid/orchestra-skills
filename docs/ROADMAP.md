# Roadmap

Orchestra's goal: **an AI engineering router that automatically chooses how much intelligence,
context and money a coding task deserves.** It's built in small releases, not all at once.

## v0.5: Token Intelligence (this release)

- Task router (tiny / small / feature / complex) **before** any expensive call
- Model policy: ROLE → MODEL with ordered fallbacks, availability, quota marking
- Token budget: expensive-call limits (a normal feature = Fable once + Opus once)
- Compact cards (minimum sufficient context) + `brief-check.sh`
- Delta retry: only the failing check, same session
- Planner ≠ Builder ≠ Reviewer
- Run metrics (`orchestra metrics`)

## v0.6: More models

- Kimi and DeepSeek set up end to end (install, login, smoke test, defaults verified)
- Automatic quota detection from relay errors → `orchestra exhausted` with the reset time
- Availability probes cached per session; `orchestra roles --refresh`
- Per-model cost/latency notes in metrics

## v0.7: Smart context

- **Repo context cache:** `.orchestra/context/{stack,architecture,conventions,testing,auth,frontend}.md`,
  generated once by a cheap model, with freshness tracking (commit hash plus changed-area detection)
- **Explorer role** (Kimi by default): before a feature/complex plan, find the relevant files,
  patterns, tests and dependencies, and summarize them in a ≤2k-token report, so the planner reads
  that instead of the repository
- Changed-area detection: only the context files for the areas a request touches
- Context freshness checks before planning

## Later

- Automatic budget tuning from past run metrics
- Per-repo policy overrides (`.orchestra/policy.json`)
- A dashboard of runs, costs and fallbacks
