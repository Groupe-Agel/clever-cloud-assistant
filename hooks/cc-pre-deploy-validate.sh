#!/usr/bin/env bash

# cc-pre-deploy-validate.sh
# Claude Code PreToolUse hook — ADVISORY ONLY, always exits 0
# Fires on: git push ... master ... --force, OR clever deploy

# Read the triggering command from stdin (Claude Code passes hook input as JSON)
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"$//' 2>/dev/null || printf '%s' "$INPUT")

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
# ---------------------------------------------------------------------------
JOURNAL_FILES=$(find . -name "_journal.json" -not -path "*/node_modules/*" 2>/dev/null)
if [ -n "$JOURNAL_FILES" ]; then
    while IFS= read -r JOURNAL_PATH; do
        [ -z "$JOURNAL_PATH" ] && continue
        JOURNAL_DIR=$(dirname "$JOURNAL_PATH")

        # Extract tags from .entries[].tag using basic shell JSON parsing
        TAGS=$(grep -o '"tag":"[^"]*"' "$JOURNAL_PATH" 2>/dev/null | sed 's/"tag":"//;s/"$//')

        while IFS= read -r TAG; do
            [ -z "$TAG" ] && continue
            SQL_FILE="${JOURNAL_DIR}/${TAG}.sql"
            if [ ! -f "$SQL_FILE" ]; then
                printf '⚠️  cc-pre-deploy: Journal tag %s has no matching SQL file. This may cause migrations to be skipped.\n' "$TAG" >&2
            fi
        done <<< "$TAGS"
    done <<< "$JOURNAL_FILES"
fi

# ---------------------------------------------------------------------------
# Check 3 — Auth
# ---------------------------------------------------------------------------
if printf '%s' "$COMMAND" | grep -q "git push"; then
    # SSH method
    SSH_KEYS=""
    SSH_KEYS=$(ssh-add -l 2>/dev/null) || true
    if [ -z "$SSH_KEYS" ] && [ -z "$GIT_SSH_COMMAND" ]; then
        printf '⚠️  cc-pre-deploy: No SSH keys loaded and GIT_SSH_COMMAND not set. SSH push may fail.\n' >&2
    fi
elif printf '%s' "$COMMAND" | grep -q "clever deploy"; then
    # Clever Cloud CLI method
    if [ -z "$CLEVER_TOKEN" ]; then
        printf '⚠️  cc-pre-deploy: CLEVER_TOKEN not set. clever deploy may require interactive login.\n' >&2
    fi
fi

exit 0
