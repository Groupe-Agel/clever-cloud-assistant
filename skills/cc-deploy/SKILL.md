---
name: cc-deploy
description: Deploy any Clever Cloud app. Covers clever CLI and SSH git push methods, pre-deploy validation checklist, force-push rationale, multi-key SSH setup, and post-deploy health invocation. Triggers on "deploy to test/prod", "push to CC", "trigger a deploy".
---

# Clever Cloud Deploy

## Pre-deploy validation checklist

Run before every deploy:
1. **Dirty working tree**: `git status --porcelain` — warn if uncommitted changes
2. **Journal integrity** (if `_journal.json` exists): verify each tag has a matching SQL file
3. **Auth**: `clever profile` exits 0 (CLI — covers both `clever login` config and `CLEVER_TOKEN`/`CLEVER_SECRET`) OR `ssh-add -l` shows loaded key (SSH)

---

## Method A — `clever` CLI (preferred)

Use when `clever` CLI is installed and authenticated (`clever profile` succeeds).

```bash
# Deploy current branch
clever deploy -f

# Deploy a specific branch
clever deploy --branch <branch> -f

# Deploy a release tag
clever deploy --tag <tag> -f

# Non-interactive CI auth
CLEVER_TOKEN=xxx CLEVER_SECRET=xxx clever deploy -f
```

**App linking:** `clever deploy` needs to know which app to target — either the repo is linked (`clever link <APP_ID>` creates `.clever.json`) or pass `--alias`/`-a <alias>` explicitly. In an unlinked directory the deploy fails immediately.

**Redeploying an unchanged commit:** `--same-commit-policy` defaults to `error` — a redeploy with no new commit fails. Use `clever deploy -f --same-commit-policy rebuild` (full rebuild) or `restart` (reuse the build), e.g. after changing a build-affecting env var.

**Important:** `clever deploy` exits at **deploy-end** (build + stream finished), not at app-healthy. A successful exit does not mean the app is running. Always invoke cc-healthcheck after. (`--exit-on never` / `--follow` keep it attached longer if needed.)

---

## Method B — SSH git push (fallback)

Use when `clever` CLI is unavailable (some CI environments).

```bash
# With dedicated key (avoids conflict with other SSH keys)
GIT_SSH_COMMAND='ssh -i ~/.ssh/clever_deploy_key -o IdentitiesOnly=yes' \
  git push git+ssh://git@<push-host>/<APP_ID>.git HEAD:master --force
```

### Getting the SSH host

**ALWAYS read the full push host from CC Console → App → Information tab → Git deployment URL.**
Do not hardcode it — hosts follow the pattern `push-<n>-<zone>-clevercloud-customers.services.clever-cloud.com` and vary by region; new zones are added over time.

Known Paris example: `push-n3-par-clevercloud-customers.services.clever-cloud.com`

### Two different CC SSH hosts (do not confuse)

| Purpose | Host |
|---|---|
| **Git deploy (push code)** | `push-<n>-<zone>-clevercloud-customers.services.clever-cloud.com` (from CC Console) |
| **SSH into running instance** | `sshgateway-clevercloud-customers.services.clever-cloud.com` |

Using the sshgateway host for git push will fail with a confusing auth error.

---

## Why force push is always required

Clever Cloud rewrites the remote history on every deployment. Your push will always be non-fast-forward. This is expected and correct — always use `--force` (SSH) or `-f` (CLI).

---

## Post-deploy

Always invoke the cc-healthcheck skill after every deploy.

- If `CC_HEALTH_CHECK_PATH` is configured in the app's env vars: CC handles health validation natively — a passing deploy already guarantees app health.
- If not configured: use the external polling loop in cc-healthcheck.

---

## Multi-app deploys

For 3+ apps: load the cc-multi-app skill (Phase 2) for ordered orchestration.
