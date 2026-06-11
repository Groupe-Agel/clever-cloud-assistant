# /cc-logs

Stream and filter logs from a Clever Cloud application.

## Usage

```
/cc-logs [--app <test|prod|APP_ID>] [--since <duration>] [--filter <pattern>]
```

## Defaults

- `--app`: test app (from CLAUDE.md)
- `--since`: `30m`
- Lines returned: last 80
- `--filter`: none (all log levels)

## Flow

### Step 1 — Resolve app

- Read app ID from CLAUDE.md for `--app test` / `--app prod`
- Default to test app if `--app` is omitted and CLAUDE.md defines one
- Use `--app <APP_ID>` directly if given

### Step 2 — Build and run command (via cc-ops agent)

Without filter:
```bash
clever logs --app <APP_ID> --since <duration> --until 5s | tail -80
```

With `--filter`:
```bash
clever logs --app <APP_ID> --since <duration> --until 5s | grep -i "<filter>" | tail -80
```

**Why `--until 5s`:** `clever logs` streams continuously and never closes the pipe — without an upper bound, `tail` waits for an EOF that never comes and the command hangs with zero output. `--until` bounds the window so the command terminates on its own (~10s).

**Duration format:** always use a unit suffix (`30m`, `2h`, `600s`). A bare number (`--since 300`) silently switches to live-streaming from now instead of fetching history.

Tip: `clever logs` also has a native `--search <pattern>` flag (server-side filter) as an alternative to `grep -i`.

Run via the Bash tool — the pipes are not PowerShell-compatible.

### Step 3 — Format output

Return: timestamp, log level, message. Strip noise (keep-alive pings, CC internal health poll lines).

## Common patterns

```
/cc-logs --filter error              # last 80 error lines from test app
/cc-logs --app prod --since 2h       # last 80 lines from prod, last 2 hours
/cc-logs --filter migration          # trace migration output
/cc-logs --filter "server listening" # confirm app started
```
