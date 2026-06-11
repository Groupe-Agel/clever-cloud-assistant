# Live Test Plan — clever-cloud-assistant

The pack was validated read-only against clever-tools v4.4.1 (every documented flag and recipe executed; see CHANGELOG). This plan covers what read-only testing **cannot** prove: live behavior inside a real Claude Code session, including an actual deploy.

**Safety rule for the whole plan: deploy/restart only TEST apps. Never run Phase 4+ against a prod app.**

---

## Prerequisites

- [ ] Pack installed (`install.ps1 -RegisterHook` / `install.sh --register-hook`) and the Claude Code session **restarted** (skills hot-load; the `cc-ops` agent and the hook only load at session start)
- [ ] `clever profile` exits 0 (authenticated)
- [ ] A disposable **test** app on Clever Cloud, linked to a local repo that has a `CLAUDE.md` with the "Clever Cloud apps" table (use `templates/CLAUDE.md.template`)
- [ ] That repo ideally uses Drizzle (to exercise the journal checks); otherwise skip the Drizzle-specific items

---

## Phase 0 — Environment sanity (2 min)

| # | Check | Pass criteria |
|---|---|---|
| 0.1 | Skills visible | `cc-deploy`, `cc-migrations`, `cc-healthcheck`, `cc-cicd` appear in the session's skill list |
| 0.2 | Commands visible | `/cc-deploy`, `/cc-logs`, `/cc-status` resolve |
| 0.3 | Agent loaded | Asking Claude to "check CC app status" routes to the `cc-ops` agent (visible as a subagent spawn), not inline Bash in the main context |
| 0.4 | Hook registered | `~/.claude/settings.json` PreToolUse (matcher `Bash`) contains `cc-pre-deploy-validate.sh` |

## Phase 1 — Read-only commands (5 min)

| # | Test | Pass criteria |
|---|---|---|
| 1.1 | `/cc-status` (no args) | Status matrix for every app in CLAUDE.md: env, app ID, status, last deploy, URL. No hang, no raw JSON |
| 1.2 | `/cc-status --app test` | Single-app detail with last 3 deployments (newest identified correctly despite oldest-first CLI output) |
| 1.3 | `/cc-logs` (defaults) | Returns ≤80 lines from the last 30 min and **terminates on its own** (the `--until` bound working) — this was the #1 pre-fix failure |
| 1.4 | `/cc-logs --filter error --since 2h` | Filtered lines only; terminates |
| 1.5 | Status matrix with no CLAUDE.md | In a directory without CLAUDE.md, `/cc-status` falls back to `clever applications list` + asks, instead of erroring |

## Phase 2 — Hook live firing (5 min)

Run these as Bash commands in the session (not in a subshell script):

| # | Test | Pass criteria |
|---|---|---|
| 2.1 | `git status` style innocuous command | Hook silent |
| 2.2 | A command containing `clever deploy` with a **dirty working tree** | Advisory warning appears (uncommitted changes); command still executes (exit 0 contract) |
| 2.3 | Same with clean tree + valid `clever login` config | No auth warning (the login-config detection working — pre-fix this false-positived) |
| 2.4 | Drizzle repo with journal tag missing its `.sql` (test fixture) | Journal warning fires on real pretty-printed `_journal.json` and respects the `drizzle/<tag>.sql` parent-dir layout |

## Phase 3 — cc-ops agent behavior (5 min)

| # | Test | Pass criteria |
|---|---|---|
| 3.1 | "Give me the status of our CC apps" | cc-ops (haiku) spawns; returns one line per app with name, status, URL (via `clever domain`); no raw JSON in main context |
| 3.2 | "Show me recent errors from <app>" | Bounded log snapshot via `--until`; ≤80 lines; filtered |
| 3.3 | "What env vars does <app> have?" | Listed and formatted; **no** `clever env import` ever suggested |

## Phase 4 — LIVE DEPLOY (test app only, 10 min)

| # | Test | Pass criteria |
|---|---|---|
| 4.1 | `/cc-deploy --app test` with a fresh commit | Pre-deploy validation runs → Method A chosen via `clever profile` (not CLEVER_TOKEN) → deploy executes → cc-healthcheck invoked automatically → report: "Deployed. App healthy at <url>" |
| 4.2 | Re-run `/cc-deploy --app test` with **no new commit** | Doesn't fail confusingly: surfaces the `--same-commit-policy` situation and proposes `rebuild`/`restart` |
| 4.3 | Health failure path (optional: temporarily break `CC_HEALTH_CHECK_PATH`) | Reports health FAILED with the bounded log command as next step; restore afterwards |
| 4.4 | SSH fallback (optional, needs deploy key) | With `clever` CLI auth removed/masked, Method B is chosen and the push URL is read from CLAUDE.md |

## Phase 5 — Skill content in anger (10 min)

| # | Test | Pass criteria |
|---|---|---|
| 5.1 | Invoke `cc-migrations` on a Drizzle repo and ask "set up migrations for this app" | Recommends `CC_PRE_RUN_HOOK` (never `CC_PRE_BUILD_HOOK`), mentions idempotency / `CC_TASK`, and the post-apply verification queries |
| 5.2 | Invoke `cc-cicd` on a fresh repo | Walks Steps 1-6; workflow templates copied are valid YAML; no AGEL-specific IDs appear |
| 5.3 | Invoke `cc-healthcheck` after 4.1 | Triage order starts with `CC_HEALTH_CHECK_PATH`, includes the `Monitoring/Unreachable` activity check |

## Phase 6 — CI templates against a sandbox repo (optional, 15 min)

Push deliberately broken states to a sandbox repo with `migrations-check.yml` active:

| # | Broken state | Expected CI result |
|---|---|---|
| 6.1 | Journal tag with no `.sql` file | Check 1 fails with the missing filename |
| 6.2 | Hand-edited journal entry with stale `when` (≤ previous entry) | Check 4 fails, prints the idx/when/tag table |
| 6.3 | Migration comment containing the literal breakpoint token | Check 5 fails, names the file and line |
| 6.4 | Squash that drops a journal entry, pushed directly | Check 3 fails using `github.event.before` (the push-event path — pre-fix this was a silent no-op) |
| 6.5 | Clean state | All 6 steps green |

---

## Result log

Copy this table when executing; anything failed → file an issue on the repo.

| Phase | Items | Pass | Fail | Notes |
|---|---|---|---|---|
| 0 | 4 | | | |
| 1 | 5 | | | |
| 2 | 4 | | | |
| 3 | 3 | | | |
| 4 | 2-4 | | | |
| 5 | 3 | | | |
| 6 | 5 | | | |
