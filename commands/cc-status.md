# /cc-status

Show the current status of all Clever Cloud apps in this project, or a single app.

## Usage

```
/cc-status [--app <test|prod|APP_ID>]
```

## Flow

### Without `--app` (default — show all)

1. Read all app IDs and URLs from CLAUDE.md "Clever Cloud apps" table
2. Via cc-ops agent: run `clever status` + `clever activity --limit 1` for each app
3. Return status matrix:

| Environment | App ID | Status | Last deploy | URL |
|---|---|---|---|---|
| test | app_xxx... | running | 2m ago | https://... |
| prod | app_yyy... | running | 1d ago | https://... |

### With `--app`

1. Resolve app ID from CLAUDE.md or use directly
2. Via cc-ops agent: `clever status` + `clever activity --limit 3`
3. Return single-app detail: status, last 3 deployments with timestamps, URL

## Status interpretation

| Status | Meaning |
|---|---|
| `running` | App is serving traffic normally |
| `stopped` | App is not running |
| `wants to be up` | Deploy in progress |
| `deploy in progress` | Build/start underway — use `/cc-logs` to follow |
| `start failed` | App crashed on start — check logs immediately |
