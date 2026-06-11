#!/usr/bin/env bash

# cc-pre-deploy-validate.sh
# Claude Code PreToolUse hook — ADVISORY ONLY, always exits 0
# Fires on: git push ... master ... --force, OR clever deploy
#
# Activation: copying this file is not enough — register it in
# ~/.claude/settings.json under hooks.PreToolUse (matcher "Bash"):
#   { "type": "command", "command": "bash ~/.claude/hooks/cc-pre-deploy-validate.sh" }

# Read the triggering command from stdin (Claude Code passes hook input as JSON).
# Prefer jq (survives escaped quotes inside the command); fall back to a
# whitespace-tolerant grep, then to raw stdin.
INPUT=$(cat)
COMMAND=""
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
fi
if [ -z "$COMMAND" ]; then
    COMMAND=$(printf '%s' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/^"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi
if [ -z "$COMMAND" ]; then
    COMMAND=$INPUT
fi

# Check if this hook should fire
IS_DEPLOY=0
if printf '%s' "$COMMAND" | grep -q "clever deploy"; then
    IS_DEPLOY=1
elif printf '%s' "$COMMAND" | grep -q "git push" && \
     printf '%s' "$COMMAND" | grep -q "master" && \
     printf '%s' "$COMMAND" | grep -q "force"; then
    IS_DEPLOY=1
fi

if [ "$IS_DEPLOY" -eq 0 ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Check 1 — Dirty working tree
# ---------------------------------------------------------------------------
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
    printf '⚠️  cc-pre-deploy: Uncommitted changes detected. Consider stashing or committing before deploying.\n' >&2
fi

# ---------------------------------------------------------------------------
# Check 2 — Drizzle journal integrity
# drizzle-kit pretty-prints the journal ("tag": "...") and puts .sql files in
# the PARENT of meta/ — tolerate whitespace and check both locations.
# ---------------------------------------------------------------------------
JOURNAL_FILES=$(find . -name "_journal.json" -not -path "*/node_modules/*" 2>/dev/null)
if [ -n "$JOURNAL_FILES" ]; then
    while IFS= read -r JOURNAL_PATH; do
        [ -z "$JOURNAL_PATH" ] && continue
        JOURNAL_DIR=$(dirname "$JOURNAL_PATH")
        MIGRATIONS_DIR=$(dirname "$JOURNAL_DIR")

        # Extract tags from .entries[].tag (whitespace-tolerant)
        if command -v jq >/dev/null 2>&1; then
            TAGS=$(jq -r '.entries[].tag' "$JOURNAL_PATH" 2>/dev/null)
        else
            TAGS=$(grep -o '"tag"[[:space:]]*:[[:space:]]*"[^"]*"' "$JOURNAL_PATH" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
        fi

        while IFS= read -r TAG; do
            [ -z "$TAG" ] && continue
            # drizzle-kit layout: drizzle/<tag>.sql (sibling of meta/);
            # also accept <tag>.sql next to the journal for custom layouts
            if [ ! -f "${MIGRATIONS_DIR}/${TAG}.sql" ] && [ ! -f "${JOURNAL_DIR}/${TAG}.sql" ]; then
                printf '⚠️  cc-pre-deploy: Journal tag %s has no matching SQL file. This may cause migrations to be skipped.\n' "$TAG" >&2
            fi
        done <<< "$TAGS"
    done <<< "$JOURNAL_FILES"
fi

# ---------------------------------------------------------------------------
# Check 3 — Auth
# ---------------------------------------------------------------------------
if printf '%s' "$COMMAND" | grep -q "clever deploy"; then
    # Clever Cloud CLI method: authenticated via `clever login` config file
    # (the normal interactive path) OR CLEVER_TOKEN/CLEVER_SECRET env vars (CI)
    CLEVER_CONFIG_UNIX="$HOME/.config/clever-cloud/clever-tools.json"
    CLEVER_CONFIG_WIN="${APPDATA:-}/clever-cloud/clever-tools.json"
    if [ -z "${CLEVER_TOKEN:-}" ] && [ ! -f "$CLEVER_CONFIG_UNIX" ] && [ ! -f "$CLEVER_CONFIG_WIN" ]; then
        printf '⚠️  cc-pre-deploy: No clever-tools login config found and CLEVER_TOKEN not set. Run `clever login` first.\n' >&2
    fi
elif printf '%s' "$COMMAND" | grep -q "git push"; then
    # SSH method
    SSH_KEYS=""
    SSH_KEYS=$(ssh-add -l 2>/dev/null) || true
    if [ -z "$SSH_KEYS" ] && [ -z "${GIT_SSH_COMMAND:-}" ]; then
        printf '⚠️  cc-pre-deploy: No SSH keys loaded and GIT_SSH_COMMAND not set. SSH push may fail.\n' >&2
    fi
fi

exit 0
