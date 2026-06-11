# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup for clever-cloud-assistant.
- `install.ps1` (Windows) and `install.sh` (Unix) installers — copy components into `~/.claude/` and optionally register the pre-deploy hook in `settings.json` (with backup, idempotent).

### Fixed
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
