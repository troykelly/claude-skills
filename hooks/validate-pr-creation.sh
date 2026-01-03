#!/usr/bin/env bash
# Validate review artifact exists before allowing PR creation
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

# Only check gh pr create commands
if ! echo "$COMMAND" | grep -q "gh pr create"; then
  exit 0
fi

# Extract issue number from command (looks for Closes #NNN, Fixes #NNN, etc.)
# Using sed instead of grep -P for macOS compatibility
ISSUE=$(echo "$COMMAND" | sed -n 's/.*\(Closes\|Fixes\|Resolves\) #\([0-9][0-9]*\).*/\2/p' | head -1)

if [ -z "$ISSUE" ]; then
  # Try to find issue from current branch name
  BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  ISSUE=$(echo "$BRANCH" | sed -n 's/.*\(feature\|fix\|bugfix\)\/\([0-9][0-9]*\).*/\2/p; s/^\([0-9][0-9]*\).*/\1/p' | head -1)
fi

if [ -z "$ISSUE" ]; then
  echo "WARNING: Could not determine issue number from PR command" >&2
  echo "Ensure PR body contains 'Closes #NNN'" >&2
  exit 0  # Allow but warn
fi

# Get repository info
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")

if [ -z "$REPO" ]; then
  echo "WARNING: Could not determine repository" >&2
  exit 0
fi

# Check for review artifact in issue comments
REVIEW_EXISTS=$(gh api "/repos/$REPO/issues/$ISSUE/comments" \
  --jq '[.[] | select(.body | contains("<!-- REVIEW:START -->"))] | length' 2>/dev/null || echo "0")

if [ "$REVIEW_EXISTS" = "0" ]; then
  log_hook_event "PreToolUse" "validate-pr-creation" "blocked" \
    "{\"issue\": $ISSUE, \"reason\": \"no_review_artifact\"}"
  cat >&2 <<EOF
REVIEW GATE BLOCKED

PR creation blocked: No review artifact found in issue #$ISSUE

Required action:
1. Complete comprehensive-review skill
2. Post review artifact to issue #$ISSUE using format:
   <!-- REVIEW:START -->
   ... (standard format)
   <!-- REVIEW:END -->
3. Ensure "Review Status: COMPLETE"
4. Ensure "Unaddressed: 0"
5. Retry PR creation

Use 'code-reviewer' subagent to perform review if needed.
EOF
  exit 2  # Deny
fi

# Check review status is COMPLETE (not BLOCKED)
REVIEW_BODY=$(gh api "/repos/$REPO/issues/$ISSUE/comments" \
  --jq '[.[] | select(.body | contains("<!-- REVIEW:START -->"))] | last | .body' 2>/dev/null || echo "")

if echo "$REVIEW_BODY" | grep -q "Review Status.*BLOCKED"; then
  log_hook_event "PreToolUse" "validate-pr-creation" "blocked" \
    "{\"issue\": $ISSUE, \"reason\": \"review_blocked\"}"
  cat >&2 <<EOF
REVIEW GATE BLOCKED

PR creation blocked: Review status is BLOCKED_ON_DEPENDENCIES

Issue #$ISSUE has deferred findings requiring resolution first.
Resolve dependency issues, then update review artifact.
EOF
  exit 2
fi

# Check unaddressed count (using sed for macOS compatibility)
UNADDRESSED=$(echo "$REVIEW_BODY" | sed -n 's/.*Unaddressed[: |]*\([0-9][0-9]*\).*/\1/p' | head -1)
UNADDRESSED="${UNADDRESSED:-0}"

if [ "$UNADDRESSED" != "0" ] && [ -n "$UNADDRESSED" ]; then
  log_hook_event "PreToolUse" "validate-pr-creation" "blocked" \
    "{\"issue\": $ISSUE, \"reason\": \"unaddressed_findings\", \"count\": $UNADDRESSED}"
  cat >&2 <<EOF
REVIEW GATE BLOCKED

PR creation blocked: $UNADDRESSED unaddressed findings

All findings must be either:
- Fixed in this PR, OR
- Deferred with tracking issues

Update review artifact to show "Unaddressed: 0"
EOF
  exit 2
fi

# All checks passed
log_hook_event "PreToolUse" "validate-pr-creation" "allowed" "{\"issue\": $ISSUE}"
exit 0
