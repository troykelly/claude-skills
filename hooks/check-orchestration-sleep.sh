#!/usr/bin/env bash
# SessionStart hook to check if orchestration should wake from sleep
#
# Checks .orchestrator/state.json for sleep status and evaluates
# if CI has completed for waiting PRs.
#
# Exit codes:
#   0 = Continue (outputs status information)
#   2 = Block with message (not used - informational only)

set -euo pipefail

# Source logging utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/log-event.sh" ]; then
  source "$SCRIPT_DIR/lib/log-event.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output goes to stderr so it appears in Claude Code
exec 1>&2

# Log this hook event
log_hook_event "SessionStart" "check-orchestration-sleep" "started" "{}"

# Find orchestration state file
STATE_FILE=""
if [ -f ".orchestrator/state.json" ]; then
  STATE_FILE=".orchestrator/state.json"
elif [ -f "${CLAUDE_PROJECT_DIR:-.}/.orchestrator/state.json" ]; then
  STATE_FILE="${CLAUDE_PROJECT_DIR}/.orchestrator/state.json"
fi

# Skip if no orchestration state
if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  log_hook_event "SessionStart" "check-orchestration-sleep" "skipped" '{"reason": "no state file"}'
  exit 0
fi

# Check if sleeping
SLEEPING=$(jq -r '.sleep.sleeping // false' "$STATE_FILE" 2>/dev/null || echo "false")

if [ "$SLEEPING" != "true" ]; then
  log_hook_event "SessionStart" "check-orchestration-sleep" "completed" '{"status": "not sleeping"}'
  exit 0
fi

# Orchestration is sleeping - gather information
REASON=$(jq -r '.sleep.reason // "unknown"' "$STATE_FILE")
SINCE=$(jq -r '.sleep.since // "unknown"' "$STATE_FILE")
WAITING_PRS=$(jq -r '.sleep.waiting_on // [] | join(", ")' "$STATE_FILE")
RESUME_SESSION=$(jq -r '.resume_session // ""' "$STATE_FILE")

echo ""
echo -e "${BLUE}[orchestration]${NC} Sleep Status Check"
echo ""
echo -e "${YELLOW}Orchestration is SLEEPING${NC}"
echo ""
echo "  Reason: $REASON"
echo "  Since: $SINCE"
echo "  Waiting on PRs: ${WAITING_PRS:-none}"
echo ""

# Check if wake conditions are met (CI complete for all PRs)
if [ -z "$WAITING_PRS" ] || [ "$WAITING_PRS" = "" ]; then
  echo -e "${YELLOW}No PRs to monitor - orchestration may need manual wake.${NC}"
  log_hook_event "SessionStart" "check-orchestration-sleep" "completed" '{"status": "sleeping", "wake": false, "reason": "no PRs to monitor"}'
  exit 0
fi

# Check each PR's CI status
echo "Checking CI status..."
echo ""

ALL_COMPLETE=true
ANY_FAILED=false
STATUSES_JSON="[]"

# Helper to add a status entry to STATUSES_JSON array
add_status() {
  local pr="$1" status="$2" passed="${3:-0}" total="${4:-0}"
  STATUSES_JSON=$(echo "$STATUSES_JSON" | jq --argjson pr "$pr" --arg status "$status" \
    --argjson passed "$passed" --argjson total "$total" \
    '. + [{"pr": $pr, "status": $status, "passed": $passed, "total": $total}]')
}

for PR in $(jq -r '.sleep.waiting_on[]' "$STATE_FILE" 2>/dev/null); do
  # Check if all checks are complete (not pending)
  CHECKS_JSON=$(gh pr checks "$PR" --json name,state,conclusion 2>/dev/null || echo "[]")

  if [ "$CHECKS_JSON" = "[]" ]; then
    echo -e "  PR #$PR: ${YELLOW}No checks found${NC}"
    add_status "$PR" "no_checks" 0 0
    continue
  fi

  PENDING=$(echo "$CHECKS_JSON" | jq 'any(.[]; .state == "PENDING")')
  FAILED=$(echo "$CHECKS_JSON" | jq 'any(.[]; .conclusion == "FAILURE")')
  ALL_SUCCESS=$(echo "$CHECKS_JSON" | jq 'all(.[]; .conclusion == "SUCCESS")')
  PASSED=$(echo "$CHECKS_JSON" | jq '[.[] | select(.conclusion == "SUCCESS")] | length')
  TOTAL=$(echo "$CHECKS_JSON" | jq 'length')

  if [ "$PENDING" = "true" ]; then
    echo -e "  PR #$PR: ${YELLOW}⏳ Running${NC} ($PASSED/$TOTAL passed)"
    ALL_COMPLETE=false
    add_status "$PR" "pending" "$PASSED" "$TOTAL"
  elif [ "$FAILED" = "true" ]; then
    echo -e "  PR #$PR: ${RED}❌ Failed${NC} ($PASSED/$TOTAL passed)"
    ANY_FAILED=true
    add_status "$PR" "failed" "$PASSED" "$TOTAL"
  elif [ "$ALL_SUCCESS" = "true" ]; then
    echo -e "  PR #$PR: ${GREEN}✅ Passed${NC} ($PASSED/$TOTAL passed)"
    add_status "$PR" "passed" "$PASSED" "$TOTAL"
  else
    echo -e "  PR #$PR: ${YELLOW}⚠️ Mixed${NC} ($PASSED/$TOTAL passed)"
    add_status "$PR" "mixed" "$PASSED" "$TOTAL"
  fi
done

echo ""

# Report wake status
if [ "$ALL_COMPLETE" = "true" ]; then
  if [ "$ANY_FAILED" = "true" ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}CI COMPLETE WITH FAILURES - ORCHESTRATION SHOULD WAKE${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Some PRs have failing CI. Investigate and fix failures."
    echo ""

    # Update state file to wake
    jq '.sleep.sleeping = false | .sleep.wake_reason = "ci_complete_with_failures"' \
      "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

    log_hook_event "SessionStart" "check-orchestration-sleep" "wake_triggered" \
      "$(json_obj_mixed "reason" "s:ci_complete_with_failures" "prs" "r:$STATUSES_JSON")"
  else
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}CI COMPLETE - ALL PASSED - ORCHESTRATION SHOULD WAKE${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "All PRs have passing CI. Resume orchestration loop."
    echo ""

    # Update state file to wake
    jq '.sleep.sleeping = false | .sleep.wake_reason = "ci_complete_all_passed"' \
      "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

    log_hook_event "SessionStart" "check-orchestration-sleep" "wake_triggered" \
      "$(json_obj_mixed "reason" "s:ci_complete_all_passed" "prs" "r:$STATUSES_JSON")"
  fi
else
  echo -e "${BLUE}CI still running. Orchestration remains asleep.${NC}"
  echo ""
  echo "To check manually: gh pr checks [PR_NUMBER]"
  if [ -n "$RESUME_SESSION" ]; then
    echo "To force wake: claude --resume $RESUME_SESSION"
  fi

  log_hook_event "SessionStart" "check-orchestration-sleep" "completed" \
    "$(json_obj_mixed "status" "s:still_sleeping" "prs" "r:$STATUSES_JSON")"
fi

echo ""

exit 0
