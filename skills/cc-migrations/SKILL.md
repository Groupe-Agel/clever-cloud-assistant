---
name: cc-migrations
description: Run database migrations safely on Clever Cloud. Covers correct hook placement (CC_PRE_RUN_HOOK not CC_PRE_BUILD_HOOK), Drizzle journal append-only rule, CC_TASK isolation pattern for migrations, rollback options, and ORM equivalents.
---

# Clever Cloud Migrations

## Hook placement — critical

| Hook | When it fires | Has node_modules? | Use for migrations? |
|---|---|---|---|
| `CC_PRE_BUILD_HOOK` | Before `npm install` | **No** | **Never** |
| `CC_POST_BUILD_HOOK` | After build, before cache | Yes | Rarely |
| `CC_PRE_RUN_HOOK` | After build + cache, before app start | **Yes** | **Always** |

```bash
# Set in CC Console → App → Environment variables
CC_PRE_RUN_HOOK=npm run db:migrate
```

**Why not CC_PRE_BUILD_HOOK?** It fires before `npm install`. No `node_modules`, no Drizzle/Prisma binaries, migration will fail with "Cannot find module".

Both `CC_PRE_BUILD_HOOK` and `CC_PRE_RUN_HOOK` fail the deployment on non-zero exit.

---

## Horizontal scaling gotcha

`CC_PRE_RUN_HOOK` runs on **every instance** when scaling horizontally (e.g. 3 instances = 3 parallel migration runs).

**Fix**: make all migrations idempotent (`IF NOT EXISTS`, upsert patterns), OR use the CC_TASK isolation pattern below.

---

## CC_TASK isolation pattern (cleanest)

Create a **dedicated migration app** in CC:

1. Set `CC_TASK=true` in app env vars
2. Set `CC_RUN_COMMAND=npm run db:migrate`
3. App runs the command once and terminates — no persistent instance cost

Deploy this task app **before** the main app in CI (`clever deploy` blocks until deploy-end, so the migration completes before the next step runs):
```yaml
env:
  CLEVER_TOKEN: ${{ secrets.CLEVER_TOKEN }}
  CLEVER_SECRET: ${{ secrets.CLEVER_SECRET }}

steps:
  - name: Run migrations
    run: clever deploy -f --app $MIGRATION_APP_ID

  - name: Deploy API
    run: clever deploy -f --app $API_APP_ID
```

Ideal for: multi-step migrations, long-running migrations, strict migration control.

---

## Drizzle journal regression

**Symptom**: migrations silently skipped; deployed code expects columns that don't exist in DB.

**Root cause**: `_journal.json` entries have modified `"when"` timestamps → Drizzle skips them.

**Rule: the journal is append-only:**
- Never edit existing `"when"` values
- Never reorder entries
- Never delete entries
- Only append new entries at the end

Add `migrations-check.yml` to CI (template in this repo) to catch regressions before deploy.

---

## Rollback (fastest-first)

1. `clever restart --commit <short-sha>` — redeploy a previous commit, no git history change
2. CC Console → Activity view → rollback button (same effect, UI-based)
3. `git revert + clever deploy -f` — safest for complex multi-file rollbacks

---

## ORM-specific

| ORM | CC_PRE_RUN_HOOK value |
|---|---|
| Drizzle | `npx drizzle-kit migrate` or `npm run db:migrate` |
| Prisma | `npx prisma migrate deploy` |
| Alembic | `alembic upgrade head` |

---

## Manual migration (emergency)

```bash
# Export CC DB connection string — CC Postgres add-ons inject
# POSTGRESQL_ADDON_URI by default; DATABASE_URL exists only if aliased
clever env | grep -E "(DATABASE_URL|POSTGRESQL_ADDON_URI)"

# Run locally against CC DB
DATABASE_URL="postgresql://..." npm run db:migrate
```
