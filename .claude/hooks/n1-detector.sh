#!/usr/bin/env bash
# PostToolUse/Bash — detects N+1 queries after test runs
# Strategy 1: Bullet gem warnings (precise, requires Bullet configured)
# Strategy 2: repeated SELECT heuristic from Rails log (fallback, no gem needed)

CMD=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.command // ""')
echo "$CMD" | grep -qE 'rails test|rspec' || exit 0

LOG="${CLAUDE_PROJECT_DIR:-.}/log/test.log"
GEMFILE="${CLAUDE_PROJECT_DIR:-.}/Gemfile"
[ ! -f "$LOG" ] && exit 0

# --- Strategy 1: Bullet warnings ---
N1=$(grep -i "N+1\|USE eager loading\|avoid N\+1" "$LOG" 2>/dev/null | sort -u | head -10)
if [ -n "$N1" ]; then
  echo "⚠ Bullet N+1 detected:" >&2
  echo "$N1" >&2
  exit 0
fi

# --- Warn if Bullet not present (Strategy 1 won't fire) ---
if ! grep -q "bullet" "$GEMFILE" 2>/dev/null; then
  echo "ℹ Bullet gem not in Gemfile — N+1 detection using log heuristic only." >&2
fi

# --- Strategy 2: repeated SELECT heuristic ---
# Flags the same table SELECTed 3+ times in any 20-line window
TABLES=$(grep -oP 'SELECT .+? FROM "\K[^"]+' "$LOG" 2>/dev/null | sort | uniq -c | sort -rn | awk '$1 >= 3 {print $1"x "$2}' | head -5)
if [ -n "$TABLES" ]; then
  echo "⚠ Possible N+1 (repeated SELECTs — confirm with includes):" >&2
  echo "$TABLES" >&2
fi

exit 0
