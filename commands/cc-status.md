# /cc-status

Show the current status of all Clever Cloud apps in this project, or a single app.

## Usage

```
/cc-status [--app <test|prod|APP_ID>]
```

## Flow

### Without `--app` (default — show all)

1. Read all app IDs and URLs from CLAUDE.md "Clever Cloud apps" table
   - If the project has no CLAUDE.md apps table: fall back to `clever applications list` and ask which apps to include
2. Via cc-ops agent: run `clever status --app <ID>` + `clever activity --app <ID> | tail -1` for each app
   - `clever activity` has **no `--limit` flag** and prints **oldest-first** — the last line is the most recent deploy
3. Return status matrix:

| Environment | App ID | Status | Last deploy | URL |
|---|---|---|---|---|
| test | app_xxx... | running | 2m ago | https://... |
| prod | app_yyy... | running | 1d ago | https://... |

### With `--app`

1. Resolve app ID from CLAUDE.md or use directly
2. Via cc-ops agent: `clever status --app <ID>` + `clever activity --app <ID> | tail -3`
3. Return single-app detail: status, last 3 deployments with timestamps, URL (`clever domain --app <ID>` if not in CLAUDE.md)

## Status interpretation

`clever status` output looks like: `running (1*XS, Commit: abc1234...)` or a stopped-state line.
`clever activity` rows end in `OK` / `FAIL` per deployment.

| Signal | Meaning |
|---|---|
| `running (N*SIZE, Commit: ...)` | App is serving traffic normally |
| `stopped` | App is not running |
| Last activity row `FAIL` | Most recent deployment failed — check `/cc-logs` |
| Status `running` but old commit | A newer deploy failed and the previous build kept serving |
