# clever-cloud-assistant

> A Claude Code extension pack that knows Clever Cloud cold.

## What it solves

Building on Clever Cloud means re-learning the same sharp edges again and again: hooks that fire in the wrong order, migrations that race the app start, SSH deploys that silently diverge from CLI deploys, log commands that dump noise instead of signal. This pack codifies the fixes so you stop losing hours to infrastructure friction.

Pain points covered:

- `CC_RUN_SUCCEEDED` fires before migrations finish — the correct hook for post-build tasks is `post-build`, not `run`
- SSH pushes bypass the Clever Cloud build pipeline and break when the remote URL changes
- Database migrations run inside the web process instead of a dedicated one-off, causing race conditions on deploy
- No pre-flight validation — bad env vars or missing addons are discovered at runtime, not before push
- `clever logs` output is unfiltered; finding errors requires manual grep across thousands of lines
- Health checks are skipped after deploy, so silent failures go undetected until users hit them
- GitHub Actions workflows re-implement Clever Cloud native deploy rather than delegating to the CC API
- `clever env set` applied one variable at a time instead of bulk-importing from `.env` files
- App status across multiple regions and environments requires running separate CLI commands manually
- CLAUDE.md is never written for CC projects, so Claude has no app IDs, zone context, or deploy method in scope

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

Copy components to your Claude Code user directory:

```
skills/    → ~/.claude/skills/
agents/    → ~/.claude/agents/
commands/  → ~/.claude/commands/
hooks/     → ~/.claude/hooks/
```

> `install.sh` coming in Phase 2.

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
# Edit: CLEVER_APP_TEST, CLEVER_APP_PROD, DEPLOY_ZONE, MIGRATION_COMMAND
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/claude-code)
- [Clever Cloud CLI](https://www.clever-cloud.com/doc/clever-tools/getting_started/) (`clever`) — required for Method A deploys
- SSH deploy key configured on your CC app — required for Method B deploys
- `jq` — used by the hook journal checks

## License

MIT — [AGEL GROUP](https://groupe-agel.com)
