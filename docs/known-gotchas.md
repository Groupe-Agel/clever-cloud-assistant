# Clever Cloud — Known Gotchas

Collected from real production incidents across 12+ apps. Each entry: symptom → root cause → fix.

**Index**: 1-10 platform basics · 11-14 runtime/instance traps · 15-16 Drizzle deep cuts · 17 git hygiene

---

## 1. SSH key: wrong host, wrong key, wrong IdentitiesOnly

**Symptom**: `Permission denied (publickey)` or silent auth failure on SSH push.

**Root causes & fixes**:
- **Two different CC SSH hosts** — do not confuse them:
  - Git deploy: `push-<n>-<zone>-clevercloud-customers.services.clever-cloud.com` (push code here — e.g. `push-n3-par-clevercloud-customers.services.clever-cloud.com`)
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

**Fix**: Always use `clever env set KEY VALUE` (two arguments) for individual vars. Treat `env import` as a nuclear option — take a backup first (`clever env > backup.env`).

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

---

## 11. Monitoring/Unreachable killswitch: CC kills busy instances

**Symptom**: A long-running background task (crawl, batch import, embedding job) dies mid-execution. DB rows stuck in `running`/`processing` forever. `clever activity` shows a deploy/restart entry triggered by **`Monitoring/Unreachable`** — not by `github` or `Console`.

**Root cause**: CC's monitor force-restarts an instance whose health endpoint stops responding (observed threshold ≈ 5 min on XS). CPU-bound or long-IO work running inside the API process starves the event loop, health checks time out, and the platform kills the instance — even though it's doing real work.

**Fix** (in order of completeness):
1. Move heavy work to a dedicated worker app (job queue; the worker doesn't serve health checks)
2. Scope each unit of work to fit under ~2 minutes
3. Add re-entrance guards + a startup janitor that reaps orphaned `running` rows
4. Bigger flavor (faster work = under the threshold) — costs more, doesn't fix the architecture

**Diagnostic habit**: whenever a background task vanished, check `clever activity` for the trigger column before chasing application bugs.

---

## 12. Build hangs forever on TypeScript validation (small instances)

**Symptom**: Deploy log shows `Compiled successfully in 20s` then `Running TypeScript ...` then nothing for 30+ minutes. Deployment stays IN PROGRESS indefinitely (CC never times out a build); the previous version keeps serving.

**Root cause**: On XS-class instances (default heap ~644MB), `next build`'s post-compile `tsc` worker competes with the compiler for heap and goes into pathological GC. Not a deadlock — practically stuck.

**Fix (immediate)**:
```bash
clever cancel-deploy --app <id>     # cancel the stuck deploy
clever restart --app <id>           # retry — the cancelled deploy's BUILD CACHE IS PRESERVED
```
The retry typically finishes in ~3 minutes thanks to the preserved cache.

**Fix (permanent)**: scale the build to a bigger flavor (`--build-flavor`), or skip type-checking in the production build (`typescript: { ignoreBuildErrors: true }` in next.config) **only if** CI type-checks before merge.

---

## 13. `clever deploy` fails with 401 on GitHub-integrated apps

**Symptom**: `clever deploy` returns 401/permission error even though `clever profile` shows you're authenticated.

**Root cause**: When an app's deploy source is CC's **native GitHub integration** (the recommended prod setup), the direct push path is rejected — deploys only happen via pushes to the tracked GitHub branch.

**Fix**: Deploy by pushing to the GitHub branch the app tracks (`git push origin main`), and monitor with `clever activity --app <id>`. Reserve `clever deploy` / SSH push for apps without the GitHub integration.

---

## 14. Small Postgres add-ons cap connections at ~5 — pg.Pool default is 10

**Symptom**: Every DB-touching endpoint 500s; dashboards show zeros with no visible error. The underlying error (often swallowed) is `53300: too_many_connections`.

**Root cause**: CC free/small PostgreSQL add-ons cap connections per role at ~5. `pg.Pool` defaults to `max: 10` and saturates the limit immediately.

**Fix**:
```typescript
new Pool({ connectionString: ..., max: 3, idleTimeoutMillis: 30000 })
```
Budget the cap across **everything** holding connections: N app instances × pool size + migration tasks + your local psql.

---

## 15. Drizzle: out-of-sync tracking table → silent full rollback, exit 0

**Symptom**: `drizzle-kit migrate` exits 0 and prints success, but the schema is unchanged. New code crashes with `column does not exist`.

**Root cause**: If `__drizzle_migrations` is empty or missing entries (typical when the initial schema was bootstrapped outside drizzle — raw SQL, dump-restore), drizzle decides ALL migrations are pending, re-runs `0000`, hits `table already exists`, rolls back the entire transaction — **and still reports success**.

**Fix**: Bootstrap the tracking table — INSERT rows marking pre-existing migrations as applied — before any future migration will apply. And never trust the exit code: after every migrate, verify `SELECT COUNT(*) FROM drizzle.__drizzle_migrations` matches the journal entry count, and check that an expected schema artifact (column/enum/index) actually exists.

---

## 16. Drizzle migration authoring rules (transaction + splitter traps)

**Symptom**: `[✓] migrations applied successfully!` but columns are missing; or `PRE_RUN_HOOK failed` / `transaction is aborted` with no useful trace.

**Root causes** (three distinct traps, one family):
- **Non-transactional statements**: a file without `--> statement-breakpoint` markers runs as ONE transaction; if any statement can't run in a transaction (`ALTER TYPE … ADD VALUE` on PG < 12), everything rolls back while drizzle still prints success
- **`DO $$ … END $$` blocks**: the splitter cuts on every `;`, tearing dollar-quoted bodies into invalid fragments
- **The splitter is comment-blind**: the literal breakpoint token inside a `--` or `/* */` comment still splits the file — the fragment after it becomes garbage SQL

**Rules**:
1. One DDL statement per `;--> statement-breakpoint`
2. Never use `DO $$` blocks in migration files — move conditional logic to application code
3. Never write the literal breakpoint token in migration comments (paraphrase it)
4. Verify post-apply (see gotcha 15) — the success message means the migrator function returned, not that the DB changed

The `migrations-check.yml` template in this repo enforces journal `when` monotonicity and rejects breakpoint tokens inside comments.

---

## 17. main/master divergence: deploys track a branch nobody commits to

**Symptom**: The deployed app behaves like an older version of the code even though your branch is green and pushed. Debugging looks like a phantom regression in someone else's work.

**Root cause**: The repo has both `main` and `master` (mixed git defaults), the PaaS deploy tracks one, and active development drifted onto the other. The fork grows silently.

**Fix**: One default branch, enforced (`gh repo create --default-branch main` + branch protection). Audit existing repos: `git log origin/main..origin/master --oneline` and the reverse — if either is non-empty, reconcile now; it only gets worse. When debugging "deployed app ignores my code", check which branch the deploy tracks **first**.
