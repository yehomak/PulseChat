#!/usr/bin/env bash
# PostToolUse/Write — auto-injects frozen_string_literal magic comment on every .rb file
FILE=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.file_path // ""')
[[ "$FILE" != *.rb ]] && exit 0
[ ! -f "$FILE" ] && exit 0
head -1 "$FILE" | grep -q 'frozen_string_literal' && exit 0
sed -i '' '1s/^/# frozen_string_literal: true\n/' "$FILE"
exit 0
