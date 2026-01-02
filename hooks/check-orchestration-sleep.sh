#!/usr/bin/env bash
# SessionStart hook to check if orchestration should wake from sleep
#
# Checks GitHub tracking issue for sleep status and evaluates
# if CI has completed for waiting PRs.
#
# Exit codes:
#   0 = Continue (outputs status information)
#   2 = Block with message (not used - informational only)
#
# State Location:
#   GitHub Issue comments with <!-- ORCHESTRATION:SLEEP --> markers
#   NO local state files - all state survives crashes

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/log-event.sh" ]; then
  source "$SCRIPT_DIR/lib/log-event.sh"
fi
if [ -f "$SCRIPT_DIR/lib/github-state.sh" ]; then
  source "$SCRIPT_DIR/lib/github-state.sh"
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

# Get tracking issue from environment or project config
TRACKING_ISSUE="${TRACKING_ISSUE:-${ORCHESTRATION_ISSUE:-}}"

# Try to find tracking issue from project if not set
if [ -z "$TRACKING_ISSUE" ]; then
  # Look for an open issue with "orchestration" label
  REPO=$(get_repo)
  if [ -n "$REPO" ]; then
    TRACKING_ISSUE=$(gh issue list --repo "$REPO" --label "orchestration" --state open --json number --jq '.[0].number // empty' 2>/dev/null || echo "")
  fi
fi

if [ -z "$TRACKING_ISSUE" ]; then
  log_hook_event "SessionStart" "check-orchestration-sleep" "skipped" '{"reason": "no tracking issue"}'
  exit 0
fi

# Get sleep status from GitHub
SLEEP_JSON=$(get_sleep_status "$TRACKING_ISSUE")

if [ -z "$SLEEP_JSON" ] || [ "$SLEEP_JSON" = "null" ]; then
  log_hook_event "SessionStart" "check-orchestration-sleep" "skipped" '{"reason": "no sleep state"}'
  exit 0
fi

# Check if sleeping
SLEEPING=$(echo "$SLEEP_JSON" | jq -r '.sleeping // false')

if [ "$SLEEPING" != "true" ]; then
  log_hook_event "SessionStart" "check-orchestration-sleep" "completed" '{"status": "not sleeping"}'
  exit 0
fi

# Orchestration is sleeping - gather information
REASON=$(echo "$SLEEP_JSON" | jq -r '.reason // "unknown"')
SINCE=$(echo "$SLEEP_JSON" | jq -r '.since // "unknown"')
WAITING_PRS=$(echo "$SLEEP_JSON" | jq -r '.waiting_on // [] | join(", ")')
RESUME_SESSION=$(echo "$SLEEP_JSON" | jq -r '.resume_session // ""')

echo ""
echo -e "${BLUE}[orchestration]${NC} Sleep Status Check"
echo ""
echo -e "${YELLOW}Orchestration is SLEEPING${NC}"
echo ""
echo "  Reason: $REASON"
echo "  Since: $SINCE"
echo "  Waiting on PRs: ${WAITING_PRS:-none}"
echo "  Tracking Issue: #$TRACKING_ISSUE"
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

for PR in $(echo "$SLEEP_JSON" | jq -r '.waiting_on[]' 2>/dev/null); do
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
    echo -e "  PR #$PR: ${YELLOW}Running${NC} ($PASSED/$TOTAL passed)"
    ALL_COMPLETE=false
    add_status "$PR" "pending" "$PASSED" "$TOTAL"
  elif [ "$FAILED" = "true" ]; then
    echo -e "  PR #$PR: ${RED}Failed${NC} ($PASSED/$TOTAL passed)"
    ANY_FAILED=true
    add_status "$PR" "failed" "$PASSED" "$TOTAL"
  elif [ "$ALL_SUCCESS" = "true" ]; then
    echo -e "  PR #$PR: ${GREEN}Passed${NC} ($PASSED/$TOTAL passed)"
    add_status "$PR" "passed" "$PASSED" "$TOTAL"
  else
    echo -e "  PR #$PR: ${YELLOW}Mixed${NC} ($PASSED/$TOTAL passed)"
    add_status "$PR" "mixed" "$PASSED" "$TOTAL"
  fi
done

echo ""

# Report wake status
if [ "$ALL_COMPLETE" = "true" ]; then
  if [ "$ANY_FAILED" = "true" ]; then
    echo -e "${YELLOW}CI COMPLETE WITH FAILURES - ORCHESTRATION SHOULD WAKE${NC}"
    echo ""
    echo "Some PRs have failing CI. Investigate and fix failures."
    echo ""

    # Wake orchestration via GitHub state
    wake_from_sleep "ci_complete_with_failures" "$TRACKING_ISSUE"

    log_hook_event "SessionStart" "check-orchestration-sleep" "wake_triggered" \
      "$(json_obj_mixed "reason" "s:ci_complete_with_failures" "prs" "r:$STATUSES_JSON")"
  else
    echo -e "${GREEN}CI COMPLETE - ALL PASSED - ORCHESTRATION SHOULD WAKE${NC}"
    echo ""
    echo "All PRs have passing CI. Resume orchestration loop."
    echo ""

    # Wake orchestration via GitHub state
    wake_from_sleep "ci_complete_all_passed" "$TRACKING_ISSUE"

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
  echo "Tracking issue: #$TRACKING_ISSUE"

  log_hook_event "SessionStart" "check-orchestration-sleep" "completed" \
    "$(json_obj_mixed "status" "s:still_sleeping" "prs" "r:$STATUSES_JSON")"
fi

echo ""

exit 0
