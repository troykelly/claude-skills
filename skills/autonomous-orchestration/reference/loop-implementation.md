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
│ MONITOR       │         │ CHECK CI/PRs  │         │ SPAWN WORKERS │
│ WORKERS       │         │               │         │               │
│               │         │ - CI status?  │         │ - Capacity?   │
│ TaskOutput()  │         │ - Ready merge?│         │ - Next issues?│
│ for each      │         │ - Failed?     │         │ - Task() with │
│ task_id       │         │               │         │   background  │
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

## Active Worker Tracking

Maintain a mapping of issue# → task_id for all active workers:

```markdown
## Active Workers State

Orchestrator maintains:
active_workers = {
  123: "aa93f22",  # Issue #123 → task_id aa93f22
  124: "b51e54b",  # Issue #124 → task_id b51e54b
  125: "c72f3d1"   # Issue #125 → task_id c72f3d1
}

This state is ephemeral (session only). Persistent state is in GitHub.
```

## Helper Functions

**All query functions use cached data. 0 API calls.**

```bash
# PREREQUISITE: GH_CACHE_ITEMS must be set by session-start via github-api-cache

get_pending_issues() {
  # Use cached data (0 API calls)
  echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "Ready") | .content.number'
}

get_in_progress_issues() {
  # Use cached data (0 API calls)
  echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "In Progress") | .content.number'
}

get_blocked_issues() {
  # Use cached data (0 API calls)
  echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "Blocked") | .content.number'
}

get_in_review_issues() {
  # Use cached data (0 API calls)
  echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "In Review") | .content.number'
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

The main loop uses Task tool to spawn workers and TaskOutput to monitor them.

### Orchestration Start

```markdown
## Starting Orchestration

1. Write active marker to MCP Memory:
   mcp__memory__create_entities([{
     "name": "ActiveOrchestration",
     "entityType": "Orchestration",
     "observations": [
       "Status: ACTIVE",
       "Scope: [MILESTONE/EPIC/unbounded]",
       "Tracking Issue: #[NUMBER]",
       "Started: [ISO_TIMESTAMP]",
       "Repository: [owner/repo]",
       "Phase: BOOTSTRAP"
     ]
   }])

2. Run bootstrap phase (resolve existing PRs)

3. Enter main loop
```

### Main Loop Implementation

```markdown
## MAIN LOOP

Each iteration:

### 1. MONITOR ACTIVE WORKERS

For each task_id in active_workers:
  TaskOutput(task_id: "[ID]", block: false, timeout: 1000)

Handle results:
- "Task is still running..." → Continue monitoring
- Completed successfully → Check GitHub for PR, update project board
- Failed/Error → Check if handover needed, possibly spawn replacement

### 2. CHECK CI/PRs

For each open PR:
  - Check CI status with: gh pr view [PR] --json statusCheckRollup
  - If all checks SUCCESS and review artifact exists:
    → gh pr merge [PR] --squash --delete-branch
    → mark_issue_done [ISSUE]
  - If FAILURE:
    → Spawn CI monitoring agent to investigate/fix

### 3. SPAWN NEW WORKERS

Calculate available slots: 5 - len(active_workers)

If slots available AND pending issues exist:
  Get next N pending issues from project board

  **IMPORTANT: Spawn ALL in ONE message for true parallelism:**

  Task(description: "Issue #123 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)
  Task(description: "Issue #124 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)
  Task(description: "Issue #125 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)

  Store returned task_ids in active_workers mapping

### 4. EVALUATE STATE

Query project board for counts:
- pending = count of "Ready" issues
- in_progress = count of "In Progress" issues
- in_review = count of "In Review" issues
- blocked = count of "Blocked" issues
- open_prs = count of open PRs

Decision logic:
- IF pending=0 AND in_progress=0 AND in_review=0 AND open_prs=0:
  → complete_orchestration(), clear_active_marker(), EXIT

- IF in_progress=0 AND pending=0 AND open_prs>0:
  → update_active_marker("SLEEPING:waiting_for_ci"), enter_sleep()

- IF in_progress=0 AND pending=0 AND blocked>0:
  → update_active_marker("SLEEPING:all_remaining_blocked"), enter_sleep()

- ELSE:
  → Continue to next iteration

### 5. BRIEF PAUSE

Wait 30 seconds before next iteration (allows CI to progress, workers to complete)
```

### Example Loop Iteration

```markdown
## Loop Iteration Example

**Active workers:** {284: "a791653", 285: "b51e54b", 286: "aa93f22"}

**Step 1: Monitor Workers**
TaskOutput(task_id: "a791653", block: false)  → "Task is still running..."
TaskOutput(task_id: "b51e54b", block: false)  → Completed with result
TaskOutput(task_id: "aa93f22", block: false)  → "Task is still running..."

Worker b51e54b completed → Check GitHub:
  gh pr list --head "feature/285-*"  → Found PR #290
  Update project board: Issue #285 → "In Review"
  Remove from active_workers: {284: "a791653", 286: "aa93f22"}

**Step 2: Check CI/PRs**
PR #290: gh pr view 290 --json statusCheckRollup
  All checks SUCCESS → gh pr merge 290 --squash --delete-branch
  mark_issue_done(285)

**Step 3: Spawn Workers**
Available slots: 5 - 2 = 3
Pending issues: #287, #288

Spawn 2 workers in ONE message:
Task(description: "Issue #287 worker", ..., run_in_background: true)
Task(description: "Issue #288 worker", ..., run_in_background: true)

Update active_workers: {284: "a791653", 286: "aa93f22", 287: "d82e3f4", 288: "e93f4a5"}

**Step 4: Evaluate**
pending=0, in_progress=4, open_prs=1 → Continue

**Step 5: Pause 30s**
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
