#!/usr/bin/env bash
# Stop event — two-attempt RuboCop gate (thoughtbot pattern)
# First Stop: auto-correct and report. Second Stop: report remaining, don't block.
INPUT=$(cat)
cd "${CLAUDE_PROJECT_DIR:-.}"

RUBY_FILES=$(git diff --name-only --diff-filter=AM HEAD -- '*.rb' '*.rake' 2>/dev/null | sort -u)
[ -z "$RUBY_FILES" ] && exit 0

if [ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ]; then
  REMAINING=$(bundle exec rubocop --force-exclusion $RUBY_FILES 2>&1)
  [ $? -ne 0 ] && echo "RuboCop violations remain after auto-correct:" >&2 && echo "$REMAINING" >&2
  exit 0
fi

OUTPUT=$(bundle exec rubocop --force-exclusion --autocorrect $RUBY_FILES 2>&1)
if [ $? -ne 0 ]; then
  echo "RuboCop violations found — fix before completing:" >&2
  echo "$OUTPUT" >&2
  exit 2
fi
exit 0
