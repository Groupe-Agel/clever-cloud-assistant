# Clever Cloud — Known Gotchas

Collected from real production incidents across 12+ apps. Each entry: symptom → root cause → fix.

---

## 1. SSH key: wrong host, wrong key, wrong IdentitiesOnly

**Symptom**: `Permission denied (publickey)` or silent auth failure on SSH push.

**Root causes & fixes**:
- **Two different CC SSH hosts** — do not confuse them:
  - Git deploy: `push.<zone>.clever-cloud.com` (push code here)
  - Instance SSH: `sshgateway-clevercloud-customers.services.clever-cloud.com` (shell access here)
- **Zone is not a marketing name** — get the exact hostname from CC Console → App → Information tab → Git deployment URL. "EU West" and "NA" are marketing names; the zone identifier in the URL (e.g. `par`, `mtl`) is what matters.
- **Multiple SSH keys conflict** — use `GIT_SSH_COMMAND='ssh -i ~/.ssh/clever_key -o IdentitiesOnly=yes'`
- Ed25519 preferred; RSA also works.

---

## 2. Force push: non-fast-forward rejection

**Symptom**: `! [rejected] HEAD -> master (non-fast-forward)`

**Root cause**: CC rewrites the remote's history on every deployment. Your push will always be non-fast-forward.

**Fix**: Always use `--force` (SSH) or `-f` (clever CLI). This is expected, not a mistake.

---

## 3. Build cache: CC_BUILD_CACHE_FOLDER does not exist

**Symptom**: Setting `CC_BUILD_CACHE_FOLDER` does nothing; cache never works.

**Root cause**: This variable does not exist in Clever Cloud.

**Fix**: Use the correct vars:
- `CC_CACHE_DEPENDENCIES=true` — enable dependency caching
- `CC_OVERRIDE_BUILDCACHE=<paths>` — specify what to cache
- `CC_IGNORE_FROM_BUILDCACHE=<paths>` — exclude paths from cache
- `CC_DISABLE_BUILD_CACHE_UPLOAD=true` — disable cache upload

To force a clean rebuild: `clever restart --without-cache`

---

## 4. Drizzle journal regression: `when` mutation

**Symptom**: Migrations silently skipped after squash or journal regeneration. Deployed code expects columns the DB doesn't have.

**Root cause**: `_journal.json` entries have modified `"when"` timestamps → Drizzle treats them as already-applied and skips them.

**Fix**: The journal is **append-only**. Never edit existing `"when"` values, never reorder, never delete. Use the `migrations-check.yml` CI guard (template in this repo) to catch regressions before deploy.

---

## 5. Migration hook placement: CC_PRE_BUILD_HOOK fires too early

**Symptom**: Migration fails with `Cannot find module` or binary not found.

**Root cause**: `CC_PRE_BUILD_HOOK` fires **before** `npm install`. No `node_modules`, no Drizzle/Prisma binaries.

**Fix**: Use `CC_PRE_RUN_HOOK` for all ORM migrations. It fires after the build, before the app starts.

**Bonus gotcha**: `CC_PRE_RUN_HOOK` runs on **every instance** when scaling horizontally. Make migration scripts idempotent, or use the `CC_TASK=true` isolation pattern.

---

## 6. Health check: build success is not app healthy

**Symptom**: Deploy "succeeded" (GitHub Actions green / CLI exits 0) but app returns 502 or is still starting.

**Root cause**: `clever deploy` exits at **deploy-end**, not at **app-healthy**.

**Fix (primary)**: Set `CC_HEALTH_CHECK_PATH=/health` — CC polls this endpoint during deployment. Non-2xx = deploy fails, old instance keeps serving (zero-downtime).

**Fix (fallback)**: Use the external polling loop in the cc-healthcheck skill.

---

## 7. Env var propagation: when to restart vs redeploy

**Symptom**: Set an env var, restarted, but app still uses the old value.

**Rule**:
- **Runtime vars** (`DATABASE_URL`, `API_KEY`, secrets): `clever restart` is enough
- **Build-affecting vars** (`CC_NODE_VERSION`, `CC_PRE_RUN_HOOK`, `CC_PRE_BUILD_HOOK`): require a **full redeploy** (new push) — a restart reuses the old build artifact

---

## 8. clever env import is destructive

**Symptom**: All environment variables gone after running `clever env import`.

**Root cause**: The CC docs warn explicitly: `clever env import` **DELETES ALL EXISTING VARIABLES** before importing.

**Fix**: Always use `clever env set KEY=VALUE` for individual vars. Treat `env import` as a nuclear option — take a backup first (`clever env > backup.env`).

---

## 9. .git deleted during build: use CC_COMMIT_ID

**Symptom**: Build scripts fail with `fatal: not a git repository` or `git rev-parse HEAD` returns empty.

**Root cause**: CC deletes the `.git` directory during build for security reasons.

**Fix**: Use the `CC_COMMIT_ID` environment variable, which CC injects automatically, instead of `git rev-parse HEAD`.

---

## 10. CC_PRE_RUN_HOOK runs N times on horizontal scale

**Symptom**: Migration race conditions, duplicate constraint violations, partial migration runs on scale-out.

**Root cause**: `CC_PRE_RUN_HOOK` runs on **every new instance** when you scale to 3+ instances. Three instances = three parallel migration executions.

**Fix**: Make all migrations idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`), OR use the `CC_TASK=true` isolation pattern (dedicated migration app that runs once and exits).
