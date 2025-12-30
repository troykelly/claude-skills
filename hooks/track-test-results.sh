#!/usr/bin/env bash
# PostToolUse hook to track test results
#
# Creates a marker file when tests pass, allowing the commit gate
# to be satisfied in validate-tests-pass.sh
#
# Exit codes:
#   0 = Always (informational only)

set -euo pipefail

# Source logging utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/log-event.sh" ]; then
  source "$SCRIPT_DIR/lib/log-event.sh"
fi

INPUT=$(cat)

# Only check Bash commands
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // .tool_result.exitCode // "unknown"')
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // .tool_result.output // ""' | head -c 1000)

# Check if this was a test command
if ! echo "$COMMAND" | grep -qE '(npm test|pnpm test|yarn test|pytest|cargo test|go test|jest|vitest|mocha|make test)'; then
  exit 0
fi

# Get or create session marker
SESSION_MARKER="/tmp/claude-session-marker"
SESSION_ID=""
if [ -f "$SESSION_MARKER" ]; then
  SESSION_ID=$(cat "$SESSION_MARKER")
else
  SESSION_ID="$$-$(date +%s)"
  echo "$SESSION_ID" > "$SESSION_MARKER"
fi

TEST_PASS_FILE="/tmp/claude-tests-passed-$SESSION_ID"

# Check if tests passed
if [ "$EXIT_CODE" = "0" ]; then
  # Tests passed - create marker
  echo "$(date -Iseconds)" > "$TEST_PASS_FILE"

  log_hook_event "PostToolUse" "track-test-results" "tests_passed" \
    "$(json_obj "command" "$(echo "$COMMAND" | head -c 100)" "marker" "$TEST_PASS_FILE")"

  echo "" >&2
  echo "[test-gate] ✅ Tests passed - commit gate satisfied" >&2
  echo "" >&2
else
  # Tests failed - remove marker if exists
  rm -f "$TEST_PASS_FILE"

  log_hook_event "PostToolUse" "track-test-results" "tests_failed" \
    "$(json_obj "command" "$(echo "$COMMAND" | head -c 100)" "exit_code" "$EXIT_CODE")"

  echo "" >&2
  echo "[test-gate] ❌ Tests failed - commit gate NOT satisfied" >&2
  echo "Fix failures and re-run tests before committing." >&2
  echo "" >&2
fi

exit 0
