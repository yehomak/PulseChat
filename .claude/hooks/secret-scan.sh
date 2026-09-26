#!/usr/bin/env bash
# PostToolUse/Write — scans written files for hardcoded secrets
FILE=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.file_path // ""')
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0
file "$FILE" | grep -q text || exit 0
echo "$FILE" | grep -qE '\.rb|\.yml|\.env|\.json' || exit 0
if grep -qE 'sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|password\s*[:=]\s*["\x27][^"]{8,}|secret_key_base\s*[:=]\s*["\x27][a-f0-9]{20,}' "$FILE" 2>/dev/null; then
  echo "Possible hardcoded secret in $FILE — use Rails credentials or ENV instead" >&2
  exit 2
fi
exit 0
