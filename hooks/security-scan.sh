#!/usr/bin/env bash
# Quick security scan on file edits
# Non-blocking - outputs warnings but doesn't prevent action
#
# Exit codes:
#   0 = Allow (always)

set -euo pipefail

# Source logging utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/log-event.sh" ]; then
  source "$SCRIPT_DIR/lib/log-event.sh"
fi

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Only scan code files
if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|rb|go|java|php|sql)$'; then
  exit 0
fi

WARNINGS=""

# Check for potential hardcoded secrets
SECRETS_FOUND=$(grep -nE "(password|secret|api_key|apikey|token|credential|private_key)\s*[:=]\s*[\"'][^\"']{8,}[\"']" "$FILE_PATH" 2>/dev/null | head -5 || true)

if [ -n "$SECRETS_FOUND" ]; then
  WARNINGS="${WARNINGS}
**Potential Hardcoded Secrets Detected**

File: $FILE_PATH

\`\`\`
$SECRETS_FOUND
\`\`\`

Please verify these are not actual credentials.
Use environment variables or secret management instead.
"
fi

# Check for SQL injection patterns (simple heuristic)
SQL_ISSUES=$(grep -nE "(query|execute|raw)\s*\(\s*[\`\"'].*\\\$\{" "$FILE_PATH" 2>/dev/null | head -3 || true)

if [ -n "$SQL_ISSUES" ]; then
  WARNINGS="${WARNINGS}
**Potential SQL Injection Pattern**

File: $FILE_PATH

\`\`\`
$SQL_ISSUES
\`\`\`

Use parameterized queries instead of string interpolation.
"
fi

# Check for dangerous eval usage
EVAL_USAGE=$(grep -nE "\beval\s*\(" "$FILE_PATH" 2>/dev/null | head -3 || true)

if [ -n "$EVAL_USAGE" ]; then
  WARNINGS="${WARNINGS}
**Dangerous eval() Usage Detected**

File: $FILE_PATH

\`\`\`
$EVAL_USAGE
\`\`\`

Avoid eval() with untrusted input.
"
fi

# Check for innerHTML (XSS risk)
INNERHTML=$(grep -nE "innerHTML\s*=" "$FILE_PATH" 2>/dev/null | head -3 || true)

if [ -n "$INNERHTML" ]; then
  WARNINGS="${WARNINGS}
**Potential XSS Risk (innerHTML)**

File: $FILE_PATH

\`\`\`
$INNERHTML
\`\`\`

Use textContent or sanitize input before using innerHTML.
"
fi

# Output warnings if any found
if [ -n "$WARNINGS" ]; then
  log_hook_event "PostToolUse" "security-scan" "warnings" \
    "$(json_obj_mixed "file" "s:$FILE_PATH" \
      "has_secrets" "b:$([ -n "$SECRETS_FOUND" ] && echo true || echo false)" \
      "has_sql" "b:$([ -n "$SQL_ISSUES" ] && echo true || echo false)" \
      "has_eval" "b:$([ -n "$EVAL_USAGE" ] && echo true || echo false)" \
      "has_xss" "b:$([ -n "$INNERHTML" ] && echo true || echo false)")"
  echo "## Security Scan Warnings"
  echo "$WARNINGS"
  echo ""
  echo "*This is an advisory scan. Review findings during code review.*"
else
  log_hook_event "PostToolUse" "security-scan" "clean" "$(json_obj "file" "$FILE_PATH")"
fi

exit 0  # Always allow - this is advisory only
