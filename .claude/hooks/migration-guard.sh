#!/usr/bin/env bash
# PreToolUse/Bash — blocks destructive Rails DB operations
CMD=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.command // ""')
echo "$CMD" | grep -qE 'db:schema:load|db:drop|db:migrate:down' || exit 0
echo "$CMD" | grep -qi 'i confirm' && exit 0
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Destructive DB operation blocked (db:schema:load / db:drop / db:migrate:down). Add \"i confirm\" to proceed."}}' && exit 0
