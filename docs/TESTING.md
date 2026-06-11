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

---

## Run 1 — 2026-06-11 (live session, OTED test apps)

Target: OTED repo (`Documents/Agel/Dev/Oted`) + OTED-BackEnd_Test (`app_cfa61ba3`) / OTED-Dashboard_Test (`app_30cb301f`). LicenseHub/AgentHub test apps no longer exist (stale IDs).

| Phase | Items | Pass | Fail | Notes |
|---|---|---|---|---|
| 0 | 4 | 4 | 0 | Skills/commands/agent all hot-loaded after restart; hook registered |
| 1 | 5 | 5 | 0 | 1.3 `--until` bound works (no hang); 1.5 fallback verified via cc-ops 58-app enumeration, not literally from a no-CLAUDE.md dir |
| 2 | 4 | 4 | 0 | Verified by direct script invocation — exit-0 hook stderr is NOT visible to the model (see finding F2) |
| 3 | 3 | 3 | 0 | cc-ops formats cleanly, no raw JSON, never suggests `clever env import` |
| 4 | 2 | 2 | 0 | 4.1 deploy+healthcheck OK (external polling — no CC_HEALTH_CHECK_PATH on app); 4.2 same-commit error surfaces clearly. 4.3/4.4 skipped (optional) |
| 5 | 3 | 3 | 0 | Templates: valid YAML, no project-specific IDs |
| 6 | 5 | — | — | Deferred (optional, needs sandbox repo) |

### Findings

- **F1 (critical, FIXED this run):** hook ran `find .` unbounded from the hook process cwd — 3m04s stall when the session starts in `$HOME`. Fixed: hook now cd's to the `cwd` from hook input JSON and scopes the journal scan to `git rev-parse --show-toplevel`; skips it outside a repo. From-home runtime: 0.65s.
- **F2 (design):** advisory warnings (stderr + exit 0) are visible only in the user's transcript, never to the model — the model cannot react to them. Acceptable for advisory-only, but document it.
- **F3 (FIXED this run):** `jq` is not installed on this machine; the `.cwd` extraction needed the same grep fallback the command extraction already had (incl. JSON `\\` → `/` unescaping for Windows paths).
- **F4 (gotcha):** after the same-commit-policy error, clever-tools v4.4.1 on Windows prints `Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), src\win\async.c` — cosmetic noise after the real error, not a failure of the deploy command itself.
- **F5 (cc-ops guideline):** the harness security-flagged cc-ops for running bare `clever env` (pulls secrets into the subagent transcript). cc-ops.md should instruct: always `clever env | grep <requested keys>` / report names-only for secrets.
- **F6 (app config):** OTED API has no `/health` endpoint and neither OTED test app sets `CC_HEALTH_CHECK_PATH` — add both to get native zero-downtime validation.
- **Open question:** a deploy of OTED-Dashboard_Test started 2026-06-11 13:41:35 triggered by "Clever Tools" — confirmed NOT from this session (cc-ops transcript audited, read-only commands only). Likely a console/CLI retry of the failed 2026-06-05 deploy.
