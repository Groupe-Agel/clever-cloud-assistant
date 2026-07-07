# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Pre-deploy hook: main/master divergence check** — warns when both `main` and `master` exist and have diverged (ahead/behind counts shown), and when the push refspec source branch is not the branch currently checked out. Encodes the counter-move from two real incidents (CFAConnect, EduChatbot) where wrong-branch hypotheses cost hours.
- **cc-deploy: post-deploy is now three mandatory gates** — (1) healthcheck, (2) migrations-actually-applied verification (the Drizzle "success message lies" checks from cc-migrations), (3) contract smoke through one real end-to-end path of the shipped feature. A deploy must not be reported successful before all applicable gates run; skipped gates must be declared, never silent.
- Initial project setup for clever-cloud-assistant.
- `install.ps1` (Windows) and `install.sh` (Unix) installers — copy components into `~/.claude/` and optionally register the pre-deploy hook in `settings.json` (with backup, idempotent).
- **7 new gotchas (11-17) sourced from real production incidents**: Monitoring/Unreachable killswitch, TypeScript build stall on small instances (+ cancel/restart cache-preservation recovery), `clever deploy` 401 on GitHub-integrated apps, Postgres add-on ~5-connection cap vs pg.Pool defaults, Drizzle out-of-sync tracking table silent rollback, Drizzle migration authoring rules (transaction/splitter/comment-blind traps), main/master divergence.
- `migrations-check.yml`: two new CI checks — journal `when` monotonicity (drizzle-orm silently skips out-of-order entries) and breakpoint-token-inside-comments rejection (the splitter is comment-blind).
- cc-migrations: "the success message lies" post-apply verification discipline, tracking-table bootstrap trap, stale-`when` recovery procedure, migration authoring rules.
- cc-deploy: GitHub-integration 401 note, `--force` does-not-override-same-commit-policy trap, stuck-build cancel/restart recovery.
- cc-healthcheck: `Monitoring/Unreachable` triage step, retroactive log retrieval with ISO-8601 bounds.

### Fixed
Findings from the live in-session test run (2026-06-11, `docs/TESTING.md` Run 1 — all executed phases green):
- **Pre-deploy hook stalled ~3 minutes per deploy** when the Claude Code session starts in a broad directory (e.g. `$HOME`): the Drizzle journal scan ran `find .` from the hook process cwd, unbounded. The hook now cd's to the `cwd` field of the hook input JSON and scopes the scan to `git rev-parse --show-toplevel`, skipping it entirely outside a git repo (0.65s from `$HOME`, was 3m04s).
- **`cwd` extraction had no jq fallback** — on machines without `jq` the hook silently kept its own cwd, so the dirty-tree and journal checks ran against the wrong directory. Added the same grep fallback used for the command string, converting JSON-escaped `\\` to `/` for Windows paths.

Findings from a full empirical test drive against clever-tools v4.4.1:
- **All log snapshot recipes hung forever** — `clever logs ... | tail` never terminates because the stream never closes. Every recipe now bounds the window with `--until 5s` (verified to exit in ~12s). Also documented: `--since`/`--until` need a unit suffix; bare numbers silently live-stream.
- **`migrations-check.yml` was invalid YAML** — shipped wrapped in markdown code fences. Fences removed; also fixed the regression check being a no-op on push events (now compares against `github.event.before`) and added a malformed-journal guard.
- **Hook's Drizzle check missed real drizzle-kit output** — tag regex didn't tolerate pretty-printed JSON, and `.sql` files were looked up in `meta/` instead of its parent. Both fixed (jq used when available); auth check now recognizes `clever login` config, not just `CLEVER_TOKEN`.
- **`clever activity --limit` doesn't exist** — replaced with `| tail -N` (output is oldest-first, documented).
- **`clever env set KEY=VALUE` is wrong syntax** — v4.4.1 takes two positional args (`set KEY VALUE`); also corrected the claim that it restarts the app.
- **CLI-vs-SSH method detection mis-routed authenticated users** — now based on `clever profile` exit code instead of `CLEVER_TOKEN` presence.
- Git push host pattern corrected to `push-<n>-<zone>-clevercloud-customers.services.clever-cloud.com` (was internally inconsistent with `deploy-test.yml`).
- Documented `clever link`/`--alias` requirement and `--same-commit-policy` default (`error`) in cc-deploy.
- cc-ops agent: added Discovery section (`clever profile`, `clever applications list`, `clever domain` for URLs).
- README: rewrote the pain-points list to match the actual gotchas, fixed placeholder names, documented hook registration in `settings.json`.
- Scrubbed a real app ID fragment from the cc-cicd example.
