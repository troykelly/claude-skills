#!/usr/bin/env bash
# PreToolUse hook to block git commit until tests pass
#
# Implements the "test-and-fix" loop pattern: Claude cannot commit
# until tests have been run and passed in this session.
#
# Uses a marker file to track test pass status.
#
# Exit codes:
#   0 = Allow
#   2 = Deny (message shown to Claude)

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

# Track when tests are run and pass
# This allows the commit gate to be satisfied
TEST_PASS_MARKER="/tmp/claude-tests-passed-$$"
SESSION_MARKER="/tmp/claude-session-marker"

# Get or create session ID
SESSION_ID=""
if [ -f "$SESSION_MARKER" ]; then
  SESSION_ID=$(cat "$SESSION_MARKER")
else
  SESSION_ID="$$-$(date +%s)"
  echo "$SESSION_ID" > "$SESSION_MARKER"
fi

TEST_PASS_FILE="/tmp/claude-tests-passed-$SESSION_ID"

# Check if this is a test command completing successfully
# We detect test runs by looking for common test runner patterns
if echo "$COMMAND" | grep -qE '(npm test|pnpm test|yarn test|pytest|cargo test|go test|jest|vitest|mocha)'; then
  # This is informational - we'll create the marker in PostToolUse
  # For now, just log that tests are being run
  log_hook_event "PreToolUse" "validate-tests-pass" "test_command_detected" \
    "{\"command\": \"$(echo "$COMMAND" | head -c 100)\"}"
  exit 0
fi

# Check if this is a git commit command
if ! echo "$COMMAND" | grep -qE 'git commit'; then
  exit 0
fi

# It's a git commit - check if tests have passed
log_hook_event "PreToolUse" "validate-tests-pass" "commit_attempted" "{}"

# Check for test pass marker
if [ -f "$TEST_PASS_FILE" ]; then
  MARKER_AGE=$(( $(date +%s) - $(stat -f %m "$TEST_PASS_FILE" 2>/dev/null || stat -c %Y "$TEST_PASS_FILE" 2>/dev/null || echo 0) ))

  # Marker must be from this session (less than 2 hours old)
  if [ "$MARKER_AGE" -lt 7200 ]; then
    log_hook_event "PreToolUse" "validate-tests-pass" "commit_allowed" \
      "{\"marker_age_seconds\": $MARKER_AGE}"
    exit 0
  fi
fi

# Check if there are any source code changes that require testing
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
SOURCE_CHANGES=$(echo "$STAGED_FILES" | grep -E '\.(ts|tsx|js|jsx|py|rb|go|rs|java|php|c|cpp|h|hpp)$' || true)

if [ -z "$SOURCE_CHANGES" ]; then
  # No source code changes - allow commit (docs, configs, etc.)
  log_hook_event "PreToolUse" "validate-tests-pass" "commit_allowed" \
    '{"reason": "no source changes"}'
  exit 0
fi

# Source code changes detected but no test pass marker
cat >&2 <<EOF
TEST GATE BLOCKED

Commit blocked: Tests must pass before committing source code changes.

Staged source files:
$(echo "$SOURCE_CHANGES" | head -10 | sed 's/^/  - /')

Required action:
1. Run tests: pnpm test (or equivalent)
2. Fix any failures
3. Retry commit after tests pass

This gate ensures CI discovers nothing new - you should find issues locally first.

Tip: If this is a documentation-only change, unstage source files:
  git reset HEAD <file>

EOF

log_hook_event "PreToolUse" "validate-tests-pass" "commit_blocked" \
  "{\"staged_files\": $(echo "$SOURCE_CHANGES" | wc -l | tr -d ' ')}"

exit 2
