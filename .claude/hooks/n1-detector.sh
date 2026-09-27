#!/usr/bin/env bash
# PostToolUse/Bash — scans test.log for Bullet N+1 warnings after test runs
CMD=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.command // ""')
echo "$CMD" | grep -qE 'rails test|rspec' || exit 0
LOG="${CLAUDE_PROJECT_DIR:-.}/log/test.log"
[ ! -f "$LOG" ] && exit 0
N1=$(grep -i "N+1\|USE eager loading\|avoid N\+1" "$LOG" 2>/dev/null | sort -u | head -10)
if [ -n "$N1" ]; then
  echo "Bullet detected N+1 queries:" >&2
  echo "$N1" >&2
fi
exit 0
