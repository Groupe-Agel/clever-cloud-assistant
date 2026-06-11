# clever-cloud-assistant

> A Claude Code extension pack that knows Clever Cloud cold.

## What it solves

Building on Clever Cloud means re-learning the same sharp edges again and again: hooks that fire in the wrong order, migrations that race the app start, SSH deploys that silently diverge from CLI deploys, log commands that dump noise instead of signal. This pack codifies the fixes so you stop losing hours to infrastructure friction.

Pain points covered (see `docs/known-gotchas.md` for the full list):

- Migrations placed in `CC_PRE_BUILD_HOOK` fail with "Cannot find module" — it fires before `npm install`; the correct hook is `CC_PRE_RUN_HOOK`
- Drizzle journal regressions: edited `"when"` timestamps make migrations silently skip, leaving prod code expecting columns the DB doesn't have
- `CC_PRE_RUN_HOOK` runs on **every** instance on horizontal scale — non-idempotent migrations race each other
- `clever logs | tail` hangs forever — the stream never closes; you need `--until` to get a snapshot
- "Deploy succeeded" ≠ "app healthy" — `clever deploy` exits at deploy-end; without `CC_HEALTH_CHECK_PATH` a crashed app goes unnoticed
- Two confusable SSH hosts (git push vs instance gateway) and zone names that aren't the marketing region names
- Force-push panic: CC rewrites its remote history by design, so non-fast-forward is *expected*
- `clever env import` silently **deletes all existing variables**
- Build-affecting env vars need a full redeploy, not a restart — and `.git` is deleted during build (`CC_COMMIT_ID` instead of `git rev-parse`)
- No project CLAUDE.md for CC apps, so Claude has no app IDs, zone, or deploy method in scope

## What's included

| Component | Name | What it does |
|---|---|---|
| Skill | cc-deploy | Deploy via CLI or SSH with pre-flight validation |
| Skill | cc-migrations | Run migrations safely with correct hook placement |
| Skill | cc-healthcheck | Verify app health after deploy |
| Skill | cc-cicd | Set up GitHub Actions → CC CI/CD pipeline |
| Agent | cc-ops | Haiku agent for all CC CLI operations |
| Command | /cc-deploy | One-command deploy with health check |
| Command | /cc-logs | Filtered log streaming |
| Command | /cc-status | App status matrix |
| Hook | cc-pre-deploy-validate | Advisory pre-deploy checks |
| Template | CLAUDE.md.template | Drop-in CLAUDE.md for any CC project |
| Templates | deploy-test.yml, migrations-check.yml | Ready-to-use GitHub Actions workflows |
| Docs | known-gotchas.md | 10 common CC pain points and fixes |

## Quick install

**Windows (PowerShell):**
```powershell
.\install.ps1 -RegisterHook
```

**macOS / Linux / Git Bash:**
```bash
./install.sh --register-hook
```

This copies skills, agent, commands, and the hook into `~/.claude/`, and (with the flag) registers the pre-deploy hook in `~/.claude/settings.json` (backup taken first). Restart your Claude Code session afterwards.

> Copying the hook file alone does nothing — PreToolUse hooks must be registered in `settings.json`. The installer handles it; doing it manually, add under `hooks.PreToolUse` (matcher `"Bash"`):
> `{ "type": "command", "command": "bash ~/.claude/hooks/cc-pre-deploy-validate.sh" }`

## Usage

```bash
# Deploy to staging with pre-flight checks and health verification
/cc-deploy --app test

# Deploy to production
/cc-deploy --app prod

# Stream filtered logs from the last 30 minutes
/cc-logs --since 30m --filter error

# Show status matrix across all configured apps
/cc-status
```

## Project CLAUDE.md

Copy `templates/CLAUDE.md.template` to your project root and fill in your app IDs, zone, and migration config. This gives Claude the context it needs to run CC operations without asking.

```bash
cp templates/CLAUDE.md.template ./CLAUDE.md
# Fill in the {{...}} placeholders: {{APP_TEST_ID}}, {{APP_PROD_ID}}, {{ZONE}},
# {{MIGRATE_COMMAND}}, {{HEALTH_ENDPOINT}}, ...
```

For CI/CD, copy the GitHub Actions templates too:

```bash
cp templates/.github/workflows/deploy-test.yml      .github/workflows/
cp templates/.github/workflows/migrations-check.yml .github/workflows/
# deploy-test.yml: set your test app ID + push host; add CLEVER_SSH_KEY secret
# migrations-check.yml: set JOURNAL_DIR to your migrations path
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/claude-code)
- [Clever Cloud CLI](https://www.clever-cloud.com/doc/clever-tools/getting_started/) (`clever`) — required for Method A deploys
- SSH deploy key configured on your CC app — required for Method B deploys
- `jq` — optional; the hook uses it when present and falls back to shell parsing without it (CI workflows do require it, but it's preinstalled on `ubuntu-latest`)

## License

MIT — [AGEL GROUP](https://groupe-agel.com)
