---
name: cc-healthcheck
description: Verify a Clever Cloud app is healthy after deployment. Covers CC_HEALTH_CHECK_PATH (native CC zero-downtime mechanism), external polling fallback, deploy lifecycle stages, log-based triage, and failure resolution path.
---

# Clever Cloud Health Check

## Deploy lifecycle

```
push → build (CC_PRE_BUILD_HOOK) → post-build (CC_POST_BUILD_HOOK) → run (CC_PRE_RUN_HOOK) → start → [health check]
```

**Critical**: `clever deploy` exits at **deploy-end** (build + deploy stream finished). The app may still be starting, migrating, or crashing. "Deploy succeeded" is not the same as "App is healthy."

---

## Primary: CC_HEALTH_CHECK_PATH (native)

```bash
# Set in CC Console → App → Environment variables (test AND prod)
CC_HEALTH_CHECK_PATH=/health
```

- CC polls this endpoint during deployment
- **Non-2xx response** → deployment fails, old instance keeps serving (zero-downtime)
- Passing deploy with this configured = app health guaranteed
- Recommended response: `{ "status": "ok", "version": "x.y.z" }`

**Configure this first.** The external polling below is a fallback for apps without it.

---

## Fallback: external polling (60s timeout)

```bash
APP_URL="https://your-app.cleverapps.io"
for i in $(seq 1 12); do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/health")
  if [ "$HTTP" = "200" ]; then
    echo "App healthy (attempt $i)"
    exit 0
  fi
  echo "Attempt $i: HTTP $HTTP — waiting 5s..."
  sleep 5
done
echo "Health check FAILED after 60s"
exit 1
```

---

## Log-based check

```bash
# Snapshot — ALWAYS bound the window with --until. clever logs streams
# continuously and never closes the pipe; without --until, tail waits for
# an EOF that never comes and the command hangs with zero output.
clever logs --app <APP_ID> --since 2h --until 5s | tail -80

# Filter errors only
clever logs --app <APP_ID> --since 30m --until 5s | grep -i error | tail -40

# Belt-and-braces variant if --until is ever unavailable:
timeout 30 clever logs --app <APP_ID> --since 2h | tail -80
```

**Duration format**: always use a unit suffix (`30m`, `2h`, `600s`). A bare number (`--since 300`) silently live-streams from now instead of fetching history — despite what `--help` suggests. Invalid values (`5x`) are also silently accepted as live-stream-only.

---

## Failure triage path

1. **Check CC_HEALTH_CHECK_PATH response** — what HTTP status is it returning?
2. **Check the deploy trigger**: `clever activity --app <id> | tail -3` — a restart triggered by **`Monitoring/Unreachable`** (instead of `github`/`Console`) means CC's monitor killed the instance because health checks timed out, typically because heavy in-process work starved the event loop. Any background task running at that moment died mid-flight.
3. **Check logs**: `clever logs --app <id> --since 2h --until 5s | tail -80`
4. **Check migration status**: did `CC_PRE_RUN_HOOK` complete? Migration errors in logs?
5. **Check env vars**: `clever env | grep -E "(DATABASE|REDIS|PORT)"` — missing required vars?
6. **Check CC Console → Activity** — deployment events and error messages

**Post-mortem on an ended deploy**: `clever logs` works retroactively with explicit bounds — `clever logs --app <id> --since "2026-06-11T14:00:00+02:00" --until "2026-06-11T14:30:00+02:00"` (ISO-8601 with explicit offset) retrieves logs from a window that's already over.

---

## Multi-app health matrix

When a project has multiple CC apps, check all after deployment. Read app IDs and URLs from project `CLAUDE.md`:

```
/cc-status
```

Or manually:
```bash
for APP_ID in $API_APP_ID $DASHBOARD_APP_ID; do
  echo "=== $APP_ID ==="
  clever status --app $APP_ID
done
```
