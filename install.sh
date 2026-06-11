#!/usr/bin/env bash
# clever-cloud-assistant installer (macOS / Linux / Git Bash)
# Copies skills, agent, commands, and hook into ~/.claude.
# --register-hook also wires the pre-deploy hook into settings.json (requires jq).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"
HOOK_CMD='bash ~/.claude/hooks/cc-pre-deploy-validate.sh'

mkdir -p "$CLAUDE/skills" "$CLAUDE/agents" "$CLAUDE/commands" "$CLAUDE/hooks"

for s in cc-cicd cc-deploy cc-migrations cc-healthcheck; do
  cp -r "$SRC/skills/$s" "$CLAUDE/skills/"
  echo "  installed skill   $s"
done
cp "$SRC/agents/cc-ops.md" "$CLAUDE/agents/"
echo "  installed agent   cc-ops"
for c in cc-deploy cc-logs cc-status; do
  cp "$SRC/commands/$c.md" "$CLAUDE/commands/"
  echo "  installed command /$c"
done
cp "$SRC/hooks/cc-pre-deploy-validate.sh" "$CLAUDE/hooks/"
chmod +x "$CLAUDE/hooks/cc-pre-deploy-validate.sh"
echo "  installed hook    cc-pre-deploy-validate.sh"

if [[ "${1:-}" == "--register-hook" ]]; then
  SETTINGS="$CLAUDE/settings.json"
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found — cannot edit settings.json automatically. Add manually:"
    echo "  { \"type\": \"command\", \"command\": \"$HOOK_CMD\" }"
    exit 0
  fi
  if [[ ! -f "$SETTINGS" ]]; then
    jq -n --arg cmd "$HOOK_CMD" \
      '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$cmd}]}]}}' > "$SETTINGS"
    echo "  created settings.json with hook registered"
  elif jq -e --arg cmd "$HOOK_CMD" \
      '.hooks.PreToolUse[]?.hooks[]? | select(.command == $cmd)' "$SETTINGS" >/dev/null; then
    echo "  hook already registered in settings.json — skipped"
  else
    cp "$SETTINGS" "$SETTINGS.bak"
    jq --arg cmd "$HOOK_CMD" '
      .hooks //= {} | .hooks.PreToolUse //= [] |
      if (.hooks.PreToolUse | map(.matcher == "Bash") | any) then
        .hooks.PreToolUse |= map(
          if .matcher == "Bash" then .hooks += [{type:"command",command:$cmd}] else . end)
      else
        .hooks.PreToolUse += [{matcher:"Bash",hooks:[{type:"command",command:$cmd}]}]
      end' "$SETTINGS.bak" > "$SETTINGS"
    echo "  registered hook in settings.json (backup at settings.json.bak)"
  fi
else
  echo ""
  echo "Hook not registered. Either re-run with --register-hook, or add this to"
  echo "~/.claude/settings.json under hooks.PreToolUse (matcher \"Bash\"):"
  echo "  { \"type\": \"command\", \"command\": \"$HOOK_CMD\" }"
fi

echo ""
echo "Done. Restart your Claude Code session to pick up the new skills."
