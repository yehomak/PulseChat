#!/usr/bin/env bash
# PostToolUse/Write — warns when symbol callback syntax is used (lambda required)
FILE=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.file_path // ""')
[[ "$FILE" != *.rb ]] && exit 0
[ ! -f "$FILE" ] && exit 0
VIOLATIONS=$(grep -nE 'after_(save|create|update|destroy|commit|create_commit|save_commit|update_commit)\s+:\w+' "$FILE" 2>/dev/null)
if [ -n "$VIOLATIONS" ]; then
  echo "Symbol callback syntax detected in $FILE — use lambda syntax instead:" >&2
  echo "$VIOLATIONS" >&2
  echo "  Wrong:   after_save :method_name" >&2
  echo "  Correct: after_save -> { method_name }" >&2
fi
exit 0
