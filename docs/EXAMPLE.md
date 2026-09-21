# Real example: "make sure patient login and register work"

This walks through one real feature on a Laravel + Inertia/React app (home-visit), from the first
prompt to the final report.

## Where do I type?

**In Claude Code, inside your project folder.** Only there.

```bash
cd ~/Herd/home-visit
claude
```

You **don't** open Codex, Antigravity or Copilot yourself. Claude starts them in the background when
a task needs them, sends each one a brief, and collects the result. You only talk to Claude.

| App | Do you open it? | Its role |
|---|---|---|
| **Claude Code** (Max subscription) | **Yes, this is where you work** | Plans (Opus), runs the checks (Opus), coordinates (Sonnet) |
| Codex (ChatGPT subscription) | No | Called automatically for `backend` / `complex` tasks |
| Antigravity | No | Called automatically for `ui` tasks |
| Copilot | No | Optional read-only reviewer |

## Before you start (once per project)

```bash
~/orchestra-skills/scripts/doctor.sh                                            # all ✓?
~/orchestra-skills/scripts/agy-allow.sh ~/Herd/home-visit --tests "php artisan test"
git status                                                                      # commit or stash work in progress first
```

**Commit your work in progress first.** The workflow commits task by task. If you have half-done
changes in the same files, they would get mixed into its commits.

## Step 1: pick the thinking model and ask

In Claude Code:

```
/model opus
```

Then paste something like this (plain language is fine):

> Use orchestrate to make sure patient login and registration work end to end.
> Patients register with name, email, phone (dial-code picker, validated with laravel-phone) and
> password; registration goes through the identity service. After register or login a patient lands
> on the patient dashboard; admins must use /admin/login. Cover: validation errors, duplicate email,
> identity service failure, wrong password, and role-based redirect. Add any missing tests and fix
> whatever fails.

## Step 2: the plan (Opus). What you'll see

Claude reads the auth code (Fortify actions, `routes/auth.php`, the register/login pages, the
existing tests) and writes `docs/plans/2026-09-21-patient-auth.md`, something like:

| ID | Task | Lane |
|---|---|---|
| T1 | Registration: validation rules, phone format, duplicate email, identity failure path + Pest tests | `backend` (Codex) |
| T2 | Login: wrong password, role redirect (patient → dashboard, admin blocked from patient login) + tests | `backend` (Codex) |
| T3 | Register/login pages: show field errors, phone input wiring, loading state | `ui` (Antigravity) |
| T4 | Fix anything pint/phpstan/types flag | `small` (Sonnet) |

**Definition of Done** (outcomes you can see), for example:
- a new patient can register with a valid phone and lands on the patient dashboard;
- an invalid phone or duplicate email shows a field error, and no identity call is made;
- a patient logging in lands on the patient dashboard; an admin is sent to `/admin/login`.

**Verify** (your project's real commands):

| Check | Command |
|---|---|
| Tests | `php artisan test --compact` |
| Format | `vendor/bin/pint --test` |
| Static analysis | `vendor/bin/phpstan analyse` |
| Frontend types / build | `npm run types:check` and `npm run build` |
| Runtime | `php artisan route:list --path=register` / `--path=login`, plus a Pest HTTP test that posts the forms |
| Manual | open `/register` in the browser and register a test patient |

## Step 3: plan approval (Opus `plan-reviewer`)

You'll see `APPROVE`, or `CHANGES REQUIRED` with a numbered list. Typical catches for auth:
"tests hit the real identity service, use `Http::fake`", "the duplicate-email case isn't tested",
"no check for the admin redirect". Claude fixes the plan and asks again. **No code is written
before `APPROVE`.**

## Step 4: building (Sonnet `lane-runner` + the coding tools)

Opus hands over to the Sonnet runner. You'll see lines like:

```
relay: completed · codex      (T1)
relay: completed · codex      (T2)
relay: completed · agy        (T3)
```

For each task the runner reviews the diff, runs the task's tests and makes one commit
(`feat: …`, `fix: …`). If Codex is out of quota, or Antigravity is blocked, the task moves to the
Claude `fallback` lane automatically.

## Step 5: done check (Opus `completion-auditor`)

Opus runs every **Verify** command and ticks off each **Definition of Done** item with `file:line`
evidence. You'll see either:

- `DONE`, or
- `GAPS: 1. no test for identity-service timeout — lane: backend`. The gap is built and committed,
  then Opus checks again.

## Step 6: the report and your part

Claude ends with the tasks and their commits, each verify command with its result, what the gates
caught, and a **manual check** for you. For example: *"open /register, register
test@example.com with +962…, and confirm you land on the patient dashboard."*

Do that check in the browser, look at `git log`, and push when you're happy.

## Who paid for what

```bash
~/orchestra-skills/scripts/token-report.sh home-visit
```

Codex runs are paid by your **ChatGPT** subscription. Antigravity runs are paid by **Google**. The
plan, the two Opus checks and the Sonnet coordination use your **Claude Max** plan. In Claude Code,
`/cost` or `/usage` shows the session's share.

## What actually happened (2026-09-21)

This example was run for real on home-visit (Laravel 12 + Fortify + Inertia React).

| Step | Who | Result |
|---|---|---|
| Work in progress | – | committed first as `b1eef13` |
| Baseline | Opus session | auth/patient tests 100/100, pint ✓, phpstan ✓, build ✓, types: 2 pre-existing errors elsewhere |
| Map the code | Sonnet `Explore` | found 9 untested behaviours, e.g. nobody had tested logging in through `/admin/login`, or an Identity outage during registration |
| Plan | Opus | T1 registration failure paths, T2 login and cross-page paths, running in parallel |
| Plan approval | Opus `plan-reviewer` | **APPROVE in round 1**, with every fact checked against the code |
| Build | Sonnet `lane-runner` → Claude Sonnet `fallback` (Codex was out of quota, so the runner switched automatically) | 10 new tests, 2 commits, 137/137 auth tests |
| Done check | Opus `completion-auditor` | **DONE in round 1**. Ran the full suite (671/671), pint, phpstan, types (no new errors), build and routes. No production bug found |
| Manual | you | register a +962 patient in the browser → patient home; log in via `/admin/login` → patient home |

Commits:

```
c09a0c1 docs: mark patient auth plan done after completion audit
b392353 test: cover login cross-page and error paths (T2)
94b747d test: cover registration failure paths (T1)
2d1270a docs: approved plan for patient auth end-to-end verification
```

Tokens:

| Step | Model | Tokens |
|---|---|---|
| Map the code | Sonnet | 74k |
| Plan approval | Opus | 28k |
| Coordination, reviews, commits | Sonnet | 62k |
| Writing the tests (T1 + T2) | Sonnet | 278k |
| Done check | Opus | 20k |

About 90% of the tokens ran on Sonnet; Opus did two short checks (48k). With Codex available, the
278k "writing the tests" row would have run on the ChatGPT subscription instead of Claude.
