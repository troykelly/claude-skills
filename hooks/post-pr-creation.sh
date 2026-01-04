#!/usr/bin/env bash
#
# post-pr-creation.sh - PostToolUse hook to inject CI monitoring reminder after PR creation
#
# Detects when `gh pr create` was run and outputs a reminder to continue with
# CI monitoring instead of stopping.
#
# Exit codes:
#   0 = Always (PostToolUse hooks can't block)
#

set -euo pipefail

# Read hook input from stdin
hook_input=$(cat)

# Extract the command that was run
command=$(echo "$hook_input" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""

# Only trigger for gh pr create commands
if ! echo "$command" | grep -qE 'gh\s+pr\s+create'; then
  exit 0
fi

# Extract PR number from output if available
output=$(echo "$hook_input" | jq -r '.tool_result.stdout // empty' 2>/dev/null) || output=""
pr_url=$(echo "$output" | grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | head -1 || true)

if [ -n "$pr_url" ]; then
  pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')

  cat >&2 <<EOF

**PR #${pr_number} CREATED - MANDATORY NEXT STEPS:**

Your work is NOT complete. You MUST now:

1. **Monitor CI** - Run: gh pr checks ${pr_number} --watch
2. **If CI fails** - Fix failures, push, monitor again
3. **If CI passes** - Merge: gh pr merge ${pr_number} --squash --delete-branch
4. **Continue working** - Pick up next issue in scope

**DO NOT stop and give a summary. Continue with CI monitoring NOW.**

EOF
fi

exit 0
