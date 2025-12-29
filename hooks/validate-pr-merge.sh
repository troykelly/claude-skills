#!/usr/bin/env bash
# Validate PR is ready for merge
#
# Exit codes:
#   0 = Allow
#   2 = Deny

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check gh pr merge commands
if ! echo "$COMMAND" | grep -q "gh pr merge"; then
  exit 0
fi

# Extract PR number
PR_NUM=$(echo "$COMMAND" | grep -oP 'gh pr merge\s+\K\d+' | head -1 || true)

if [ -z "$PR_NUM" ]; then
  exit 0  # Can't determine PR, allow and let gh handle it
fi

# Get PR details
PR_DATA=$(gh pr view "$PR_NUM" --json state,mergeable,reviewDecision,statusCheckRollup 2>/dev/null || echo "{}")

if [ "$PR_DATA" = "{}" ]; then
  exit 0  # Can't get PR data, allow and let gh handle it
fi

# Check mergeable status
MERGEABLE=$(echo "$PR_DATA" | jq -r '.mergeable // "UNKNOWN"')

if [ "$MERGEABLE" = "CONFLICTING" ]; then
  cat >&2 <<EOF
MERGE BLOCKED

PR #$PR_NUM has merge conflicts.

Resolve conflicts before merging:
1. git fetch origin
2. git rebase origin/main (or merge)
3. Resolve conflicts
4. git push --force-with-lease
EOF
  exit 2
fi

# Check CI status - get failed or pending checks
FAILED_CHECKS=$(echo "$PR_DATA" | jq -r '.statusCheckRollup // [] | map(select(.conclusion == "FAILURE")) | length')
PENDING_CHECKS=$(echo "$PR_DATA" | jq -r '.statusCheckRollup // [] | map(select(.status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING")) | length')

if [ "$FAILED_CHECKS" != "0" ] && [ -n "$FAILED_CHECKS" ]; then
  cat >&2 <<EOF
MERGE BLOCKED

PR #$PR_NUM has $FAILED_CHECKS failing CI checks.

Run 'gh pr checks $PR_NUM' to see status.
Fix failures before merging.
EOF
  exit 2
fi

if [ "$PENDING_CHECKS" != "0" ] && [ -n "$PENDING_CHECKS" ]; then
  cat >&2 <<EOF
MERGE BLOCKED

PR #$PR_NUM has $PENDING_CHECKS pending CI checks.

Wait for CI to complete before merging.
Run 'gh pr checks $PR_NUM' to monitor status.
EOF
  exit 2
fi

exit 0
