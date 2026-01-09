# State Management Reference

## Core Principle

**GitHub Project Board is THE source of truth for all state.** NOT labels. NOT local files. The project board.

State is tracked via:
1. **GitHub Project Board Status Field** - THE source of truth
2. **GitHub Issue Comments** - Activity log and context (supplementary)
3. **Labels** - Only for lineage tracking, NOT for state

## Project Board Status Field

| Status | Description | Transition From |
|--------|-------------|-----------------|
| Backlog | Not ready for work | (initial) |
| Ready | Ready for work, pending assignment | Backlog |
| In Progress | Worker assigned and working | Ready, Blocked |
| In Review | PR created, awaiting merge | In Progress |
| Blocked | Cannot proceed | Any |
| Done | Completed | In Review |

## Labels (Supplementary Only)

| Label | Purpose | NOT Used For |
|-------|---------|--------------|
| `review-finding` | Origin tracking | State |
| `spawned-from:#N` | Lineage tracking | State |
| `depth:N` | Recursion limit | State |
| `epic-[name]` | Epic grouping | State |

**CRITICAL:** Do NOT use labels like `status:pending` or `status:in-progress`. Use the project board.

## State Queries via Project Board

**CRITICAL: Use cached data from `github-api-cache`. ALL queries use 0 API calls.**

```bash
# PREREQUISITE: GH_CACHE_ITEMS must be set by session-start via github-api-cache

# Get pending issues in scope (Status = Ready) - 0 API calls
echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "Ready") | .content.number'

# Get in-progress issues (Status = In Progress) - 0 API calls
echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "In Progress") | .content.number'

# Get blocked issues (Status = Blocked) - 0 API calls
echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "Blocked") | .content.number'

# Get issues in review (Status = In Review) - 0 API calls
echo "$GH_CACHE_ITEMS" | jq -r '.items[] | select(.status.name == "In Review") | .content.number'

# Count by status - 0 API calls
echo "$GH_CACHE_ITEMS" | jq '[.items[] | select(.status.name == "In Progress")] | length'
```

## State Updates via Project Board

**Uses cached IDs. 1 API call for update, 1 API call to refresh cache.**

```bash
update_project_status() {
  local issue=$1
  local new_status=$2  # Ready, In Progress, In Review, Blocked, Done

  # Get item ID FROM CACHE (0 API calls)
  ITEM_ID=$(echo "$GH_CACHE_ITEMS" | jq -r ".items[] | select(.content.number == $issue) | .id")

  if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
    echo "ERROR: Issue #$issue not in project board. Add it first."
    return 1
  fi

  # Use cached IDs (0 API calls) - GH_PROJECT_ID, GH_STATUS_FIELD_ID set by session-start
  # Get option ID from cached environment variable or lookup from cache
  local option_id
  case "$new_status" in
    "Backlog")     option_id="$GH_STATUS_BACKLOG_ID" ;;
    "Ready")       option_id="$GH_STATUS_READY_ID" ;;
    "In Progress") option_id="$GH_STATUS_IN_PROGRESS_ID" ;;
    "In Review")   option_id="$GH_STATUS_IN_REVIEW_ID" ;;
    "Done")        option_id="$GH_STATUS_DONE_ID" ;;
    "Blocked")     option_id="$GH_STATUS_BLOCKED_ID" ;;
    *)
      option_id=$(echo "$GH_CACHE_FIELDS" | jq -r ".fields[] | select(.name == \"Status\") | .options[] | select(.name == \"$new_status\") | .id")
      ;;
  esac

  # Update status (1 API call)
  gh project item-edit --project-id "$GH_PROJECT_ID" --id "$ITEM_ID" \
    --field-id "$GH_STATUS_FIELD_ID" --single-select-option-id "$option_id"

  # Refresh cache and verify (1 API call)
  export GH_CACHE_ITEMS=$(gh project item-list "$GITHUB_PROJECT_NUM" --owner "$GH_PROJECT_OWNER" --format json)
  ACTUAL=$(echo "$GH_CACHE_ITEMS" | jq -r ".items[] | select(.content.number == $issue) | .status.name")

  if [ "$ACTUAL" != "$new_status" ]; then
    echo "ERROR: Status update failed. Expected $new_status, got $ACTUAL"
    return 1
  fi

  echo "Updated issue #$issue status to $new_status"
  return 0
}
```

## Orchestration Comment Template

Post to tracking issue:

```markdown
## Orchestration Status

**ID:** orch-[TIMESTAMP]
**Scope:** [MILESTONE/EPIC]
**Started:** [ISO_TIMESTAMP]
**Last Update:** [ISO_TIMESTAMP]

### Queue Status

| Status | Count | Issues |
|--------|-------|--------|
| Pending | [N] | #1, #2, #3 |
| In Progress | [N] | #4, #5 |
| Awaiting Dependencies | [N] | #6 (→ #7, #8) |
| Completed | [N] | #9, #10 |
| Blocked | [N] | #11 |

### Active Workers

| Worker | Issue | Started | Status |
|--------|-------|---------|--------|
| worker-001 | #4 | [TIME] | Implementing |
| worker-002 | #5 | [TIME] | In Review |

---
*Updated: [TIMESTAMP]*
```

## Deviation Handling

When a worker creates child issues (deferred review findings):

1. Update parent status to `Blocked` on project board
2. Add `spawned-from:#PARENT` label to children
3. Add `depth:N` label (N = parent_depth + 1)
4. Post deviation comment to parent issue

### Deviation Comment Template

```markdown
## Deviation: Awaiting Child Issues

**Project Status:** Blocked (updated in project board)
**Return When:** All children closed

### Child Issues Created

| # | Title | Created From | Status |
|---|-------|--------------|--------|
| #7 | [Title] | Review finding | Open |
| #8 | [Title] | Review finding | Open |

**Process:** Children follow full `issue-driven-development` workflow.
When all children are closed, this issue will be resumed.

---
*Worker: [WORKER_ID]*
```

## Deviation Resolution

```bash
check_deviation_resolution() {
  local issue=$1
  local open_children=$(gh issue list --label "spawned-from:#$issue" --state open --json number --jq 'length')

  if [ "$open_children" = "0" ]; then
    # All children closed, resume parent via PROJECT BOARD
    update_project_status "$issue" "Ready"

    gh issue comment "$issue" --body "## Deviation Resolved

All child issues are now closed. Ready to resume.

**Project Status:** Ready (updated in project board)

---
*Orchestrator: $ORCHESTRATION_ID*"
    return 0
  fi
  return 1
}
```

## Child Issue Lifecycle

**CRITICAL:** Child issues MUST follow the FULL `issue-driven-development` process:

1. They get their own workers
2. They go through all 13 steps
3. They have their own code reviews
4. Their findings create grandchildren if needed
5. They cannot skip any workflow step

The `depth:N` label tracks lineage to prevent infinite loops (max depth: 5).
