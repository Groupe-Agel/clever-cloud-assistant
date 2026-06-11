---
name: cc-cicd
description: Set up CI/CD for any project hosted on Clever Cloud. Covers GitHub Actions → SSH git push for staging, Clever Cloud native GitHub integration for production, SSH key setup, and migration sanity checks. Use when creating a new repo or adding deploy pipelines.
---

# Clever Cloud CI/CD Pipeline

## Architecture

| Branch | Environment | Deploy trigger |
|--------|-------------|----------------|
| `main` | Production | CC native GitHub integration — no workflow needed |
| `test` / `staging` | Staging | GitHub Actions → SSH git push on every push |
| `feat/*` | Local/PR | CI only (lint, typecheck, build — no deploy) |

No Docker. Clever Cloud apps run natively (Node, Python, Java, etc.).

---

## Step 1 — Create CC apps

In CC Console or via `clever` CLI:
1. Create **test** and **prod** apps
2. Note both App IDs (`app_xxxxxxxx-...`) — you'll need them in the workflow and CLAUDE.md
3. Configure env vars on each app — note CC add-ons inject their own names (Postgres: `POSTGRESQL_ADDON_URI`, Redis: `REDIS_HOST`/`REDIS_PORT`/`REDIS_PASSWORD`); alias to `DATABASE_URL` etc. if your app expects those
4. **Prod only**: CC Console → App → Information → GitHub integration → branch: `main` (replaces a workflow entirely)

---

## Step 2 — SSH deploy key for GitHub Actions

```bash
# Generate a dedicated deploy key
ssh-keygen -t ed25519 -C "github-actions-deploy" -f clever_deploy_key -N ""
```

1. Add **public key** (`clever_deploy_key.pub`) to: CC Console → Profile → SSH keys (or App → Deploy keys)
2. Add **private key** contents as GitHub secret: Settings → Secrets → Actions → `CLEVER_SSH_KEY`

---

## Step 3 — `.github/workflows/deploy.yml`

Copy `templates/.github/workflows/deploy-test.yml` from this repo and replace:
- `APP_TEST_ID` → your actual test app ID (e.g. `app_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- SSH host → get from CC Console → App (test) → Information tab → Git deployment URL

**Why the SSH host is not hardcoded:** zone identifiers change by region and Clever Cloud adds new zones. The authoritative source is always the CC Console Information tab.

Known Paris host example: `push-n3-par-clevercloud-customers.services.clever-cloud.com`

> **Why `HEAD:master`?** CC always deploys from its internal `master` branch.
> **Why `--force`?** CC's remote diverges from your history by design.

---

## Step 4 — (Optional) Migration safety check

If the repo has database migrations (Drizzle, Prisma, Alembic), copy `templates/.github/workflows/migrations-check.yml` and set `JOURNAL_DIR` to your migrations path.

This catches the class of prod outages where `_journal.json` entries are silently dropped and Drizzle migrate skips them.

---

## Step 5 — (Alternative) CLI deploys in CI instead of SSH

The default pipeline (Steps 2-3) deploys via SSH push and needs only the `CLEVER_SSH_KEY` secret. If you prefer the `clever` CLI in CI instead:

```yaml
env:
  CLEVER_TOKEN: ${{ secrets.CLEVER_TOKEN }}
  CLEVER_SECRET: ${{ secrets.CLEVER_SECRET }}

steps:
  - run: npm install -g clever-tools
  - run: clever deploy -f --app $APP_TEST_ID
```
Get token + secret from: CC Console → Profile → OAuth tokens. Both are required — `CLEVER_TOKEN` alone does not authenticate.

---

## Step 6 — Document apps in CLAUDE.md

Use `templates/CLAUDE.md.template` from this repo — it covers the apps table, branch convention, migrations (`CC_PRE_RUN_HOOK`), health check, and runtime-vs-build env var classes. Minimal inline version:

```markdown
## Clever Cloud apps

| Environment | App name | App ID | SSH zone | URL |
|---|---|---|---|---|
| test | MyApp_Test | app_xxxxxxxx-... | par (from CC Console → App → Information) | https://app-xxx.cleverapps.io |
| prod | MyApp_Prod | app_yyyyyyyy-... | par | https://app-yyy.cleverapps.io |
```

---

## Checklist

- [ ] Create test + prod CC apps
- [ ] Configure env vars on both apps in CC Console
- [ ] Connect prod app to GitHub `main` via CC native integration
- [ ] Generate SSH deploy key, add public key to CC, add private key as `CLEVER_SSH_KEY` in GitHub Secrets
- [ ] Create `.github/workflows/deploy.yml` (from template) with correct test app ID and SSH host
- [ ] (If has migrations) Create `.github/workflows/migrations-check.yml` (from template)
- [ ] Add CC app IDs and URLs to `CLAUDE.md`
- [ ] Push to `test` branch — verify deploy succeeds in GitHub Actions
- [ ] Push to `main` — verify CC Console shows deployment triggered
