#!/usr/bin/env bash
# Validate local service testing evidence before allowing PR creation
#
# This hook checks if changes require local service testing and verifies
# that testing evidence has been posted to the GitHub issue.
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

# Check if docker-compose exists (if not, no services to test against)
COMPOSE_FILE=""
if [ -f "docker-compose.yml" ]; then
  COMPOSE_FILE="docker-compose.yml"
elif [ -f "docker-compose.yaml" ]; then
  COMPOSE_FILE="docker-compose.yaml"
elif [ -f ".devcontainer/docker-compose.yml" ]; then
  COMPOSE_FILE=".devcontainer/docker-compose.yml"
fi

if [ -z "$COMPOSE_FILE" ]; then
  # No docker-compose, no service testing required
  exit 0
fi

# Check if changed files require service testing
CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null || git diff --cached --name-only 2>/dev/null || echo "")

REQUIRES_POSTGRES=false
REQUIRES_REDIS=false

# Patterns that indicate database/ORM changes
if echo "$CHANGED_FILES" | grep -qiE '\.(sql)$|migration|model|entity|schema|repository|orm'; then
  REQUIRES_POSTGRES=true
fi

# Patterns that indicate cache/redis changes
if echo "$CHANGED_FILES" | grep -qiE 'cache|redis|session|queue|pub|sub|worker|job'; then
  REQUIRES_REDIS=true
fi

# If no service-dependent changes, allow
if [ "$REQUIRES_POSTGRES" = "false" ] && [ "$REQUIRES_REDIS" = "false" ]; then
  exit 0
fi

# Build description of required services
REQUIRED_SERVICES=""
if [ "$REQUIRES_POSTGRES" = "true" ]; then
  REQUIRED_SERVICES="postgres"
fi
if [ "$REQUIRES_REDIS" = "true" ]; then
  if [ -n "$REQUIRED_SERVICES" ]; then
    REQUIRED_SERVICES="$REQUIRED_SERVICES, redis"
  else
    REQUIRED_SERVICES="redis"
  fi
fi

# Extract issue number from command (using sed for macOS compatibility)
ISSUE=$(echo "$COMMAND" | sed -n 's/.*\(Closes\|Fixes\|Resolves\) #\([0-9][0-9]*\).*/\2/p' | head -1)

if [ -z "$ISSUE" ]; then
  # Try to find issue from current branch name
  BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  ISSUE=$(echo "$BRANCH" | sed -n 's/.*\(feature\|fix\|bugfix\|issue-\)\([0-9][0-9]*\).*/\2/p' | head -1)
fi

if [ -z "$ISSUE" ]; then
  # Cannot verify - warn but allow
  cat >&2 <<EOF
WARNING: Local service testing required but could not verify

Changes detected that may require testing against: $REQUIRED_SERVICES

Changed files:
$(echo "$CHANGED_FILES" | grep -iE 'sql|migration|model|entity|schema|repository|orm|cache|redis|session|queue|pub|sub|worker|job' | head -10)

Ensure you have:
1. Started services: docker-compose up -d
2. Run integration tests against real services
3. Verified migrations apply to real database

Proceeding based on trust.
EOF
  exit 0
fi

# Get repository info
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")

if [ -z "$REPO" ]; then
  echo "WARNING: Could not determine repository - proceeding based on trust" >&2
  exit 0
fi

# Check for local testing artifact in issue comments
TESTING_EXISTS=$(gh api "/repos/$REPO/issues/$ISSUE/comments" \
  --jq '[.[] | select(.body | contains("<!-- LOCAL-TESTING:START -->"))] | length' 2>/dev/null || echo "0")

if [ "$TESTING_EXISTS" = "0" ]; then
  log_hook_event "PreToolUse" "validate-local-testing" "blocked" \
    "{\"issue\": $ISSUE, \"reason\": \"no_testing_evidence\", \"services\": \"$REQUIRED_SERVICES\"}"
  cat >&2 <<EOF
LOCAL TESTING GATE BLOCKED

PR creation blocked: No local service testing evidence found in issue #$ISSUE

Changes detected that require local service testing:
$(echo "$CHANGED_FILES" | grep -iE 'sql|migration|model|entity|schema|repository|orm|cache|redis|session|queue|pub|sub|worker|job' | head -10 | sed 's/^/  - /')

Required services: $REQUIRED_SERVICES

Required action:
1. Start services: docker-compose up -d $REQUIRED_SERVICES
2. Run integration tests: pnpm test:integration
3. Verify migrations: pnpm migrate (if applicable)
4. Post testing evidence to issue #$ISSUE using format:

   <!-- LOCAL-TESTING:START -->
   ## Local Service Testing

   | Service | Status | Verification |
   |---------|--------|--------------|
   | postgres | ✅ Running | Migrations applied, queries executed |

   **Tests Run:**
   - pnpm test:integration - PASSED

   **Tested At:** $(date -Iseconds)
   <!-- LOCAL-TESTING:END -->

5. Retry PR creation

Remember: CI discovers nothing. If you haven't tested locally, you're hiding bugs.
EOF
  exit 2  # Deny
fi

# Artifact exists, allow
log_hook_event "PreToolUse" "validate-local-testing" "allowed" "{\"issue\": $ISSUE}"
exit 0
