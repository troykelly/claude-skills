# Orchestration Loop Implementation

## PR Resolution Bootstrap

**CRITICAL:** This runs ONCE before the main loop starts. Resolves existing PRs before spawning new work.

```bash
resolve_existing_prs() {
  echo "=== PR RESOLUTION BOOTSTRAP ==="

  # Get all open PRs, excluding release placeholders and holds
  OPEN_PRS=$(gh pr list --json number,headRefName,labels \
    --jq '[.[] | select(
      (.headRefName | startswith("release/") | not) and
      (.labels | map(.name) | index("release-placeholder") | not) and
      (.labels | map(.name) | index("do-not-merge") | not)
    )] | .[].number')

  if [ -z "$OPEN_PRS" ]; then
    echo "No actionable PRs to resolve. Proceeding to main loop."
    return 0
  fi

  echo "Found PRs to resolve: $OPEN_PRS"

  for pr in $OPEN_PRS; do
    echo "Processing PR #$pr..."

    # Get CI status
    ci_status=$(gh pr checks "$pr" --json state --jq '.[].state' 2>/dev/null | sort -u)

    # Get linked issue
    ISSUE=$(gh pr view "$pr" --json body --jq '.body' | grep -oE 'Closes #[0-9]+' | grep -oE '[0-9]+' | head -1)

    if [ -z "$ISSUE" ]; then
      echo "  ⚠ No linked issue found, skipping"
      continue
    fi

    # Check if CI passed
    if echo "$ci_status" | grep -q "FAILURE"; then
      echo "  ❌ CI failing - triggering ci-monitoring for PR #$pr"
      handle_ci_failure "$pr"
      continue
    fi

    if echo "$ci_status" | grep -q "PENDING"; then
      echo "  ⏳ CI pending for PR #$pr, will check in main loop"
      continue
    fi

    if echo "$ci_status" | grep -q "SUCCESS"; then
      # Verify review artifact
      REVIEW_EXISTS=$(gh api "/repos/$OWNER/$REPO/issues/$ISSUE/comments" \
        --jq '[.[] | select(.body | contains("<!-- REVIEW:START -->"))] | length' 2>/dev/null || echo "0")

      if [ "$REVIEW_EXISTS" = "0" ]; then
        echo "  ⚠ No review artifact - requesting review for #$ISSUE"
        gh issue comment "$ISSUE" --body "## Review Required

PR #$pr has passing CI but no review artifact.

**Action needed:** Complete comprehensive-review and post artifact to this issue.

---
*Bootstrap phase - Orchestrator*"
        continue
      fi

      # All checks pass - merge
      echo "  ✅ Merging PR #$pr"
      gh pr merge "$pr" --squash --delete-branch
      mark_issue_done "$ISSUE"
    fi
  done

  echo "=== BOOTSTRAP COMPLETE ==="
}
```

## Loop Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MAIN LOOP                                       │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│ CHECK WORKERS │         │ CHECK CI/PRs  │         │ SPAWN/MANAGE  │
│               │         │               │         │               │
│ - Still alive?│         │ - CI status?  │         │ - Capacity?   │
│ - Completed?  │         │ - Ready merge?│         │ - Next issue? │
│ - Handover?   │         │ - Failed?     │         │ - Spawn worker│
│ - Failed?     │         │               │         │               │
└───────┬───────┘         └───────┬───────┘         └───────┬───────┘
        │                         │                         │
        └─────────────────────────┼─────────────────────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │ EVALUATE STATE    │
                        │                   │
                        │ All done? → Exit  │
                        │ All waiting? →    │
                        │   SLEEP           │
                        │ Work to do? →     │
                        │   Continue        │
                        └───────────────────┘
```

## Helper Functions

```bash
get_pending_issues() {
  gh project item-list "$GITHUB_PROJECT_NUM" --owner "$GH_PROJECT_OWNER" \
    --format json | jq -r '.items[] | select(.status.name == "Ready") | .content.number'
}

get_in_progress_issues() {
  gh project item-list "$GITHUB_PROJECT_NUM" --owner "$GH_PROJECT_OWNER" \
    --format json | jq -r '.items[] | select(.status.name == "In Progress") | .content.number'
}

get_blocked_issues() {
  gh project item-list "$GITHUB_PROJECT_NUM" --owner "$GH_PROJECT_OWNER" \
    --format json | jq -r '.items[] | select(.status.name == "Blocked") | .content.number'
}

get_in_review_issues() {
  gh project item-list "$GITHUB_PROJECT_NUM" --owner "$GH_PROJECT_OWNER" \
    --format json | jq -r '.items[] | select(.status.name == "In Review") | .content.number'
}

mark_issue_in_progress() {
  local issue=$1
  local worker=$2

  update_project_status "$issue" "In Progress"

  gh issue comment "$issue" --body "## Worker Assigned

**Worker:** \`$worker\`
**Started:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Project Status:** In Progress

---
*Orchestrator: $ORCHESTRATION_ID*"
}

mark_issue_in_review() {
  local issue=$1
  local pr=$2

  update_project_status "$issue" "In Review"

  gh issue comment "$issue" --body "## PR Created

**PR:** #$pr
**Project Status:** In Review

---
*Orchestrator: $ORCHESTRATION_ID*"
}

mark_issue_blocked() {
  local issue=$1
  local reason=$2

  update_project_status "$issue" "Blocked"

  gh issue comment "$issue" --body "## Issue Blocked

**Reason:** $reason
**Project Status:** Blocked

---
*Orchestrator: $ORCHESTRATION_ID*"
}

mark_issue_done() {
  local issue=$1

  update_project_status "$issue" "Done"

  gh issue comment "$issue" --body "## Issue Complete

**Project Status:** Done

---
*Orchestrator: $ORCHESTRATION_ID*"
}
```

## Main Loop

```bash
# ═══════════════════════════════════════════════════════════════════
# ORCHESTRATION START: Write active marker to MCP Memory
# ═══════════════════════════════════════════════════════════════════
write_active_marker() {
  mcp__memory__create_entities([{
    "name": "ActiveOrchestration",
    "entityType": "Orchestration",
    "observations": [
      "Status: ACTIVE",
      "Scope: $SCOPE",
      "Tracking Issue: #$TRACKING_ISSUE",
      "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "Repository: $OWNER/$REPO",
      "Phase: BOOTSTRAP",
      "Last Loop: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ]
  }])
}

update_active_marker() {
  local phase=$1
  mcp__memory__add_observations({
    "observations": [{
      "entityName": "ActiveOrchestration",
      "contents": [
        "Phase: $phase",
        "Last Loop: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      ]
    }]
  })
}

clear_active_marker() {
  mcp__memory__delete_entities({
    "entityNames": ["ActiveOrchestration"]
  })
}

# Write marker at orchestration start
write_active_marker

# ═══════════════════════════════════════════════════════════════════
# BOOTSTRAP: Resolve existing PRs before spawning new work
# ═══════════════════════════════════════════════════════════════════
resolve_existing_prs
update_active_marker "MAIN_LOOP"

# ═══════════════════════════════════════════════════════════════════
# MAIN LOOP: Continuous orchestration
# ═══════════════════════════════════════════════════════════════════
while true; do
  # Update marker on each iteration (survives compaction)
  update_active_marker "MAIN_LOOP"

  # Post status update to tracking issue
  post_orchestration_status

  # ─────────────────────────────────────────────────────────────
  # 1. CHECK FOR DEVIATION RESOLUTION
  # ─────────────────────────────────────────────────────────────
  for issue in $(gh issue list --label "spawned-from:" --state closed --json number --jq '.[].number' 2>/dev/null | sort -u); do
    parent=$(gh issue view "$issue" --json labels --jq '.labels[] | select(.name | startswith("spawned-from:")) | .name' | sed 's/spawned-from:#//')
    if [ -n "$parent" ]; then
      check_deviation_resolution "$parent"
    fi
  done

  # ─────────────────────────────────────────────────────────────
  # 2. CHECK CI/PRs
  # ─────────────────────────────────────────────────────────────
  for pr in $(gh pr list --json number --jq '.[].number'); do
    ci_status=$(gh pr checks "$pr" --json state --jq '.[].state' | sort -u)

    if echo "$ci_status" | grep -q "SUCCESS"; then
      # Verify review artifact exists before merge
      ISSUE=$(gh pr view "$pr" --json body --jq '.body' | grep -oE 'Closes #[0-9]+' | grep -oE '[0-9]+')
      REVIEW_EXISTS=$(gh api "/repos/$OWNER/$REPO/issues/$ISSUE/comments" \
        --jq '[.[] | select(.body | contains("<!-- REVIEW:START -->"))] | length' 2>/dev/null || echo "0")

      if [ "$REVIEW_EXISTS" = "0" ]; then
        gh pr comment "$pr" --body "Merge Blocked: No review artifact found in issue #$ISSUE.
Complete comprehensive-review and post artifact to issue before merge."
        continue
      fi

      if [ "$AUTO_MERGE" = "true" ]; then
        gh pr merge "$pr" --squash --auto
        mark_issue_done "$ISSUE"
      fi
    elif echo "$ci_status" | grep -q "FAILURE"; then
      handle_ci_failure "$pr"
    fi
  done

  # ─────────────────────────────────────────────────────────────
  # 3. SPAWN NEW WORKERS
  # ─────────────────────────────────────────────────────────────
  active_count=$(get_in_progress_issues | wc -l | tr -d ' ')

  while [ "$active_count" -lt 5 ]; do
    next_issue=$(get_pending_issues | head -1)

    if [ -z "$next_issue" ]; then
      break
    fi

    worker_id="worker-$(date +%s)-$next_issue"
    mark_issue_in_progress "$next_issue" "$worker_id"
    spawn_worker "$next_issue" "$worker_id"
    active_count=$((active_count + 1))
  done

  # ─────────────────────────────────────────────────────────────
  # 4. EVALUATE STATE
  # ─────────────────────────────────────────────────────────────
  pending=$(get_pending_issues | wc -l | tr -d ' ')
  in_progress=$(get_in_progress_issues | wc -l | tr -d ' ')
  in_review=$(get_in_review_issues | wc -l | tr -d ' ')
  blocked=$(get_blocked_issues | wc -l | tr -d ' ')
  open_prs=$(gh pr list --json number --jq 'length')

  if [ "$pending" -eq 0 ] && [ "$in_progress" -eq 0 ] && [ "$in_review" -eq 0 ] && [ "$open_prs" -eq 0 ]; then
    complete_orchestration
    clear_active_marker  # Remove marker - orchestration complete
    exit 0
  fi

  if [ "$in_progress" -eq 0 ] && [ "$pending" -eq 0 ] && [ "$open_prs" -gt 0 ]; then
    update_active_marker "SLEEPING:waiting_for_ci"  # Keep marker - will resume on CI complete
    enter_sleep "waiting_for_ci"
    exit 0
  fi

  if [ "$in_progress" -eq 0 ] && [ "$pending" -eq 0 ] && [ "$blocked" -gt 0 ]; then
    update_active_marker "SLEEPING:all_remaining_blocked"  # Keep marker - will resume when unblocked
    enter_sleep "all_remaining_blocked"
    exit 0
  fi

  # ─────────────────────────────────────────────────────────────
  # 5. BRIEF PAUSE
  # ─────────────────────────────────────────────────────────────
  sleep 30
done
```

## Status Reporting

```bash
post_orchestration_status() {
  TRACKING_ISSUE=$(gh issue list --label "orchestration-tracking" --json number --jq '.[0].number')

  # Query state from project board
  PENDING_LIST=$(get_pending_issues | tr '\n' ',' | sed 's/,$//')
  IN_PROGRESS_LIST=$(get_in_progress_issues | tr '\n' ',' | sed 's/,$//')
  BLOCKED_LIST=$(get_blocked_issues | tr '\n' ',' | sed 's/,$//')
  OPEN_PRS=$(gh pr list --json number,title --jq '.[] | "#\(.number): \(.title)"' | head -5)

  gh issue comment "$TRACKING_ISSUE" --body "## Orchestration Status

**ID:** $ORCHESTRATION_ID
**Updated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Issue Status

| Status | Issues |
|--------|--------|
| Ready | ${PENDING_LIST:-none} |
| In Progress | ${IN_PROGRESS_LIST:-none} |
| Blocked | ${BLOCKED_LIST:-none} |

### Open PRs

$OPEN_PRS

---
*Updated automatically*"
}
```
