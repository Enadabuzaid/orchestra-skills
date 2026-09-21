# Security

## What Orchestra does with your credentials

- Nothing. The scripts make no network calls and read no credentials. Each CLI (Claude, Codex,
  Antigravity, Copilot, Kimi, OpenCode) authenticates itself exactly as it does at your terminal.
- Claude runs are started with `ANTHROPIC_API_KEY` removed from the environment, so they bill your
  claude.ai subscription, not an API key, unless you set `ORCHESTRA_USE_API_KEY=1`.

## Permissions

- Builders write only inside the repo you point them at; planners, reviewers and auditors run
  read-only, and so do their fallbacks.
- Orchestra never passes `--dangerously-skip-permissions` or `--allow-all-tools`, and never edits a
  tool's permission config on its own. `scripts/agy-allow.sh` adds scoped Antigravity rules for one
  folder only, with a backup.
- Workers never commit or push; the orchestrator commits after running the gates.

## What to keep out of cards

Task cards are sent to third-party models. Never put secrets, `.env` contents, customer data or
private keys in a card. `scripts/brief-check.sh` rejects pasted file contents, but it can't
recognise every secret.

## Reporting a vulnerability

Open a private security advisory on GitHub (Security → Report a vulnerability) rather than a public
issue. Please include the affected script or skill and how to reproduce.
