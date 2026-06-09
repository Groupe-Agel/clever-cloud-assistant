# /cc-deploy

Deploy a Clever Cloud application with pre-flight checks and automatic health verification.

## Usage

```
/cc-deploy [--app <test|prod|APP_ID>]
```

## Prerequisites

- Project `CLAUDE.md` must contain a "Clever Cloud apps" table with app IDs, zones, and URLs
- Either: `clever` CLI installed + `CLEVER_TOKEN` set — OR — SSH deploy key loaded (`ssh-add`)

## Flow

### Step 1 — Resolve target app

- `--app test` → look up test app ID from CLAUDE.md
- `--app prod` → look up prod app ID from CLAUDE.md
- `--app <APP_ID>` → use directly
- No `--app` → ask which environment before proceeding

### Step 2 — Pre-deploy validation (via cc-ops agent)

Run all checks; warn but do not block on advisory issues:

1. `git status --porcelain` — warn if dirty working tree
2. Find `_journal.json` — verify each tag has a matching SQL file (Drizzle regression guard)
3. Auth: test `clever status` (CLI method) OR `ssh-add -l` (SSH method)

### Step 3 — Choose deploy method

Detect which method is available:
- `clever` CLI installed AND `CLEVER_TOKEN` set → **Method A (CLI)**
- Otherwise → **Method B (SSH)**

**Method A — clever CLI:**
```bash
clever deploy -f
```

**Method B — SSH git push:**
```bash
GIT_SSH_COMMAND='ssh -i ~/.ssh/clever_deploy_key -o IdentitiesOnly=yes' \
  git push git+ssh://git@push.<zone>.clever-cloud.com/<APP_ID>.git HEAD:master --force
```
(Zone and APP_ID read from CLAUDE.md)

### Step 4 — Post-deploy health check

Load the cc-healthcheck skill:
- If `CC_HEALTH_CHECK_PATH` is configured in CC env vars → deploy passing already confirmed health; report success
- If not → run external polling loop (12 × 5s = 60s)

### Step 5 — Report result

**Success:**
> Deployed `<app-name>` to `<env>`. App healthy at `<url>`.

**Health failure:**
> Deploy pushed. Health check FAILED after 60s.
> Next: `clever logs --app <id> --since 10m | tail -80`
