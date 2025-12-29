---
name: autonomous-orchestration
description: Use when user confirms autonomous operation across multiple issues. Orchestrates parallel workers, monitors progress, handles SLEEP/WAKE cycles, and works until scope is complete.
---

# Autonomous Orchestration

## Overview

Orchestrates long-running autonomous work across multiple issues, spawning parallel workers, monitoring CI, and persisting state across sessions.

**Core principle:** GitHub is the source of truth. Workers are disposable. State survives restarts.

**Announce at start:** "I'm using autonomous-orchestration to work through [SCOPE]. This requires your explicit confirmation for autonomous operation."

## Prerequisites

- `worker-dispatch` skill for spawning workers
- `worker-protocol` skill for worker behavior
- `ci-monitor` skill for CI/WAKE handling
- Git worktrees support (workers use isolated worktrees)
- GitHub CLI (`gh`) authenticated

## User Confirmation Required

**CRITICAL:** Never begin autonomous operation without explicit user confirmation.

```markdown
## Autonomous Operation Request

⚠️ **Extended autonomous operation requires your explicit approval.**

**Scope:** [MILESTONE/EPIC/ISSUES]
**Estimated workers:** [N]
**Parallel limit:** 5 workers max

This will:
1. Spawn worker processes for each issue
2. Create git worktrees for isolation
3. Workers implement, test, and create PRs
4. Monitor CI and auto-merge when green
5. SLEEP while waiting, WAKE when ready
6. Continue until all issues resolved (or blocked)

**Type PROCEED to confirm autonomous operation.**
```

Only proceed when user types exactly: `PROCEED`

## State Management (GitHub-Native)

**Core principle:** GitHub is the ONLY source of truth. No filesystem state files.

State is tracked via:
1. **GitHub Labels** - Issue/PR status
2. **GitHub Issue Comments** - Activity log and context
3. **GitHub Project Fields** - Orchestration tracking

### GitHub Labels for State

| Label | Description | Applied To |
|-------|-------------|------------|
| `status:pending` | Ready for work | Issues |
| `status:in-progress` | Worker assigned | Issues |
| `status:awaiting-dependencies` | Blocked on child issues | Issues |
| `status:blocked` | Truly blocked | Issues |
| `review-finding` | Created from review | Issues |
| `spawned-from:#N` | Lineage tracking | Issues |
| `depth:N` | Issue depth (1=child, 2=grandchild) | Issues |

### Create Labels (Run Once)

```bash
# Run scripts/create-labels.sh or:
gh label create "status:pending" --color "0E8A16" --description "Ready for work" --force 2>/dev/null || true
gh label create "status:in-progress" --color "1D76DB" --description "Worker assigned" --force 2>/dev/null || true
gh label create "status:awaiting-dependencies" --color "FBCA04" --description "Blocked on child issues" --force 2>/dev/null || true
gh label create "status:blocked" --color "D93F0B" --description "Truly blocked" --force 2>/dev/null || true
gh label create "review-finding" --color "C2E0C6" --description "Created from code review" --force 2>/dev/null || true
```

### State Queries via GitHub API

```bash
# Get pending issues in scope
gh issue list --milestone "v1.0.0" --label "status:pending" --json number --jq '.[].number'

# Get in-progress issues
gh issue list --milestone "v1.0.0" --label "status:in-progress" --json number --jq '.[].number'

# Get issues awaiting dependencies
gh issue list --label "status:awaiting-dependencies" --json number,labels --jq '.[] | {number, spawned_from: (.labels[] | select(.name | startswith("spawned-from:")) | .name)}'

# Get review-finding child issues for parent #123
gh issue list --label "spawned-from:#123" --json number,state --jq '.'

# Count active workers (issues in-progress)
gh issue list --label "status:in-progress" --json number --jq 'length'
```

### Orchestration Comment Template

Post to milestone/epic tracking issue:

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

### Deviation Tracking

Issues requiring return after child completion:

| Parent | Status | Children | Return When |
|--------|--------|----------|-------------|
| #6 | Awaiting | #7, #8 | All children closed |

---
*Updated: [TIMESTAMP]*
```

### Deviation Handling

When a worker creates child issues (e.g., deferred review findings):

1. Mark parent with `status:awaiting-dependencies`
2. Add `spawned-from:#PARENT` label to children
3. Add `depth:N` label (N = parent_depth + 1)
4. Post deviation comment to parent issue:

```markdown
## Deviation: Awaiting Child Issues

**Status:** `awaiting-dependencies`
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

### Child Issue Lifecycle

**CRITICAL:** Child issues (from review findings) MUST follow the FULL `issue-driven-development` process:

1. They get their own workers
2. They go through all 13 steps
3. They have their own code reviews
4. Their findings create grandchildren if needed
5. They cannot skip any workflow step

The `depth:N` label tracks lineage to prevent infinite loops (max depth: 5).

### Deviation Resolution

When monitoring for deviation resolution:

```bash
# Check if all children of #123 are closed
OPEN_CHILDREN=$(gh issue list --label "spawned-from:#123" --state open --json number --jq 'length')

if [ "$OPEN_CHILDREN" = "0" ]; then
  # All children closed, resume parent
  gh issue edit 123 --remove-label "status:awaiting-dependencies" --add-label "status:pending"
  gh issue comment 123 --body "## Deviation Resolved

All child issues are now closed. This issue is ready to resume.

**Children Completed:**
$(gh issue list --label "spawned-from:#123" --state closed --json number,title --jq '.[] | "- #\(.number): \(.title)"')

---
*Orchestrator: [ORCHESTRATION_ID]*"
fi
```

## Orchestration Loop

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MAIN LOOP                                       │
└─────────────────────────────────────────┬───────────────────────────────────┘
                                          │
        ┌─────────────────────────────────┼─────────────────────────────────┐
        ▼                                 ▼                                 ▼
┌───────────────┐               ┌───────────────┐               ┌───────────────┐
│ CHECK WORKERS │               │ CHECK CI/PRs  │               │ SPAWN/MANAGE  │
│               │               │               │               │               │
│ - Still alive?│               │ - CI status?  │               │ - Capacity?   │
│ - Completed?  │               │ - Ready merge?│               │ - Next issue? │
│ - Handover?   │               │ - Failed?     │               │ - Spawn worker│
│ - Failed?     │               │               │               │               │
└───────┬───────┘               └───────┬───────┘               └───────┬───────┘
        │                               │                               │
        └───────────────────────────────┼───────────────────────────────┘
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

### Loop Implementation (GitHub-Native)

```bash
# Helper functions using GitHub as state store

get_pending_issues() {
  gh issue list --milestone "$MILESTONE" --label "status:pending" --json number --jq '.[].number'
}

get_in_progress_issues() {
  gh issue list --milestone "$MILESTONE" --label "status:in-progress" --json number --jq '.[].number'
}

get_awaiting_issues() {
  gh issue list --milestone "$MILESTONE" --label "status:awaiting-dependencies" --json number --jq '.[].number'
}

check_deviation_resolution() {
  local issue=$1
  local open_children=$(gh issue list --label "spawned-from:#$issue" --state open --json number --jq 'length')
  if [ "$open_children" = "0" ]; then
    # All children closed, resume parent
    gh issue edit "$issue" --remove-label "status:awaiting-dependencies" --add-label "status:pending"
    gh issue comment "$issue" --body "## Deviation Resolved

All child issues are now closed. Ready to resume.

---
*Orchestrator: $ORCHESTRATION_ID*"
    return 0
  fi
  return 1
}

mark_issue_in_progress() {
  local issue=$1
  local worker=$2
  gh issue edit "$issue" --remove-label "status:pending" --add-label "status:in-progress"
  gh issue comment "$issue" --body "## Worker Assigned

**Worker:** \`$worker\`
**Started:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

---
*Orchestrator: $ORCHESTRATION_ID*"
}

# Main orchestration loop
while true; do
  # Post status update to tracking issue
  post_orchestration_status

  # ─────────────────────────────────────────────────────────────
  # 1. CHECK DEVIATION RESOLUTIONS
  # ─────────────────────────────────────────────────────────────
  for issue in $(get_awaiting_issues); do
    check_deviation_resolution "$issue"
  done

  # ─────────────────────────────────────────────────────────────
  # 2. CHECK CI/PRs (with review verification)
  # ─────────────────────────────────────────────────────────────
  for pr in $(gh pr list --json number --jq '.[].number'); do
    ci_status=$(gh pr checks "$pr" --json state --jq '.[].state' | sort -u)

    if echo "$ci_status" | grep -q "SUCCESS"; then
      # Verify review artifact exists before merge
      ISSUE=$(gh pr view "$pr" --json body --jq '.body' | grep -oE 'Closes #[0-9]+' | grep -oE '[0-9]+')
      REVIEW_EXISTS=$(gh api "/repos/$OWNER/$REPO/issues/$ISSUE/comments" \
        --jq '[.[] | select(.body | contains("<!-- REVIEW:START -->"))] | length' 2>/dev/null || echo "0")

      if [ "$REVIEW_EXISTS" = "0" ]; then
        gh pr comment "$pr" --body "⚠️ **Merge Blocked:** No review artifact found in issue #$ISSUE.

Complete \`comprehensive-review\` and post artifact to issue before merge."
        continue
      fi

      if [ "$AUTO_MERGE" = "true" ]; then
        gh pr merge "$pr" --squash --auto
        gh issue comment "$ISSUE" --body "## PR Merged

PR #$pr merged automatically after CI passed.

---
*Orchestrator: $ORCHESTRATION_ID*"
      fi
    elif echo "$ci_status" | grep -q "FAILURE"; then
      handle_ci_failure "$pr"
    fi
  done

  # ─────────────────────────────────────────────────────────────
  # 3. SPAWN NEW WORKERS (respecting capacity)
  # ─────────────────────────────────────────────────────────────
  active_count=$(get_in_progress_issues | wc -l | tr -d ' ')

  while [ "$active_count" -lt 5 ]; do
    next_issue=$(get_pending_issues | head -1)

    if [ -z "$next_issue" ]; then
      break  # No more issues to work
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
  awaiting=$(get_awaiting_issues | wc -l | tr -d ' ')
  open_prs=$(gh pr list --json number --jq 'length')

  if [ "$pending" -eq 0 ] && [ "$in_progress" -eq 0 ] && [ "$awaiting" -eq 0 ] && [ "$open_prs" -eq 0 ]; then
    # All done!
    complete_orchestration
    exit 0
  fi

  if [ "$in_progress" -eq 0 ] && [ "$pending" -eq 0 ] && [ "$open_prs" -gt 0 ]; then
    # Nothing to do but wait for CI
    enter_sleep "waiting_for_ci"
    exit 0  # Will be woken by wake mechanism
  fi

  if [ "$in_progress" -eq 0 ] && [ "$pending" -eq 0 ] && [ "$awaiting" -gt 0 ]; then
    # Waiting for child issues
    enter_sleep "waiting_for_child_issues"
    exit 0
  fi

  # ─────────────────────────────────────────────────────────────
  # 5. BRIEF PAUSE BEFORE NEXT ITERATION
  # ─────────────────────────────────────────────────────────────
  sleep 30  # Check every 30 seconds when active
done
```

## Scope Types

### Milestone

```bash
# Get issues in milestone
gh issue list --milestone "v1.0.0" --state open --json number --jq '.[].number'
```

### Epic

```bash
# Get issues with epic label
gh issue list --label "epic-dark-mode" --state open --json number --jq '.[].number'
```

### Issue List

```bash
# Explicit list
ISSUES="123 124 125 126"
```

### Unbounded (All Open Issues)

```markdown
⚠️ **UNBOUNDED MODE WARNING**

You have requested unbounded orchestration (work until no open issues).

This will:
- Work through ALL open issues in the repository
- Continue indefinitely until complete
- Only stop when no issues remain or all are blocked

**This is potentially dangerous.** Are you sure?

Type UNBOUNDED to confirm, or specify a scope instead.
```

```bash
# All open issues
gh issue list --state open --json number --jq '.[].number'
```

## Failure Handling

### Retry with Research

Workers that fail do NOT immediately become blocked. The cycle is:

```
Attempt 1 (Failed)
       │
       ▼
Research Cycle 1 (via research-after-failure skill)
       │
       ▼
Attempt 2 (Failed)
       │
       ▼
Research Cycle 2 (deeper research)
       │
       ▼
Attempt 3 (Failed)
       │
       ▼
Research Cycle 3 (exhaustive research)
       │
       ▼
Attempt 4 (Failed)
       │
       ▼
ONLY NOW: Mark as Blocked
```

### Research Cycle Implementation

```bash
trigger_research_cycle() {
  worker=$1
  issue=$(get_worker_issue "$worker")
  cycle=$(get_research_cycle_count "$issue")

  # Spawn research worker (read-only tools)
  claude -p "$(cat <<PROMPT
You are a research agent investigating why issue #$issue is failing.

## Research Cycle: $((cycle + 1))

## Previous Attempts
$(get_attempt_history "$issue")

## Your Task
1. Analyze the failure logs
2. Research the problem thoroughly
3. Document findings in issue #$issue
4. Propose a new approach

## Constraints
- You are READ-ONLY - do not modify code
- Focus on understanding, not fixing
- Be thorough - this is attempt $((cycle + 1))

Begin by reading the worker logs and issue comments.
PROMPT
)" \
    --allowedTools "Read,Grep,Glob,WebFetch,WebSearch,mcp__memory__*" \
    --max-turns 50 \
    --output-format json \
    > ".orchestrator/logs/research-$issue-$cycle.log" 2>&1

  # After research, spawn new worker with research context
  increment_research_cycle "$issue"
  spawn_worker "$issue" --with-research-context
}
```

### Blocked Determination

An issue is only marked blocked when:

1. Multiple research cycles completed (3+)
2. Research concludes "impossible without external input"
3. Examples of true blockers:
   - Missing API credentials
   - Requires decision from human
   - External service unavailable
   - Dependency on unreleased feature

```bash
mark_issue_blocked() {
  issue=$1
  reason=$2

  gh issue comment "$issue" --body "## 🚫 Issue Blocked

**Reason:** $reason

**Attempts:** $(get_attempt_count "$issue")
**Research Cycles:** $(get_research_cycle_count "$issue")

**Why Blocked:**
This issue cannot proceed without external intervention.

**Required Action:**
$reason

---
*Orchestration ID: $ORCHESTRATION_ID*"

  gh issue edit "$issue" --add-label "blocked"
  update_queue_blocked "$issue"
}
```

## Git Worktree Isolation

Workers use separate git worktrees to avoid conflicts:

```bash
# Create worktree for worker
create_worker_worktree() {
  issue=$1
  worker_id=$2
  branch="feature/$issue-$(slugify_issue_title "$issue")"
  worktree_path="../$(basename $PWD)-worker-$issue"

  # Create branch if not exists
  git branch "$branch" 2>/dev/null || true

  # Create worktree
  git worktree add "$worktree_path" "$branch"

  echo "$worktree_path"
}

# Cleanup worktree after worker done
cleanup_worker_worktree() {
  worktree_path=$1

  # Remove worktree
  git worktree remove "$worktree_path" --force

  # Prune worktree references
  git worktree prune
}
```

## SLEEP/WAKE

### Entering SLEEP

```bash
enter_sleep() {
  reason=$1

  # Post sleep status to tracking issue (GitHub-native)
  TRACKING_ISSUE=$(gh issue list --label "orchestration-tracking" --json number --jq '.[0].number')
  WAITING_PRS=$(gh pr list --json number --jq '[.[].number] | join(", ")')
  WAITING_CHILDREN=$(gh issue list --label "status:awaiting-dependencies" --json number --jq '[.[].number] | join(", ")')

  gh issue comment "$TRACKING_ISSUE" --body "## Orchestration Sleeping

**Reason:** $reason
**Since:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Waiting On

| Type | Items |
|------|-------|
| PRs in CI | $WAITING_PRS |
| Child Issues | $WAITING_CHILDREN |

### Wake Mechanisms

- **Polling:** Every 5 minutes
- **Manual:** \`claude --resume $RESUME_SESSION\`

---
*Orchestrator: $ORCHESTRATION_ID*"

  # Report to user
  echo "## Orchestration Sleeping"
  echo ""
  echo "**Reason:** $reason"
  echo "**Waiting on PRs:** $WAITING_PRS"
  echo "**Waiting on children:** $WAITING_CHILDREN"
  echo ""
  echo "Wake mechanisms active:"
  echo "- Polling: Every 5 minutes"
  echo "- Manual: claude --resume $RESUME_SESSION"
}
```

### WAKE Mechanisms

See `ci-monitor` skill for detailed WAKE implementations:
- Polling script
- SessionStart hook
- Webhook server (with port safety)

## Status Reporting (GitHub-Native)

Status is posted as a comment on the tracking issue:

```bash
post_orchestration_status() {
  TRACKING_ISSUE=$(gh issue list --label "orchestration-tracking" --json number --jq '.[0].number')

  # Query all state from GitHub
  PENDING=$(gh issue list --milestone "$MILESTONE" --label "status:pending" --json number --jq '[.[].number] | join(", ")')
  IN_PROGRESS=$(gh issue list --milestone "$MILESTONE" --label "status:in-progress" --json number,title --jq '.[] | "| #\(.number) | \(.title) |"')
  AWAITING=$(gh issue list --milestone "$MILESTONE" --label "status:awaiting-dependencies" --json number --jq '[.[].number] | join(", ")')
  BLOCKED=$(gh issue list --milestone "$MILESTONE" --label "status:blocked" --json number --jq '[.[].number] | join(", ")')
  COMPLETED=$(gh issue list --milestone "$MILESTONE" --state closed --json number --jq '[.[].number] | join(", ")')
  OPEN_PRS=$(gh pr list --json number,title,statusCheckRollup --jq '.[] | "| #\(.number) | \(.title) | \(.statusCheckRollup | map(.state) | unique | join(",")) |"')

  gh issue comment "$TRACKING_ISSUE" --body "## Orchestration Status

**ID:** $ORCHESTRATION_ID
**Scope:** $MILESTONE
**Updated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Issue Status

| Status | Issues |
|--------|--------|
| Pending | $PENDING |
| In Progress | (see below) |
| Awaiting Dependencies | $AWAITING |
| Blocked | $BLOCKED |
| Completed | $COMPLETED |

### Active Workers

| Issue | Title |
|-------|-------|
$IN_PROGRESS

### Open PRs

| PR | Title | CI Status |
|----|-------|-----------|
$OPEN_PRS

### Deviation Tracking

Issues waiting on children:

\`\`\`
$(for issue in $(gh issue list --label "status:awaiting-dependencies" --json number --jq '.[].number'); do
  children=$(gh issue list --label "spawned-from:#$issue" --state open --json number --jq '[.[].number] | join(", ")')
  echo "#$issue → waiting on: $children"
done)
\`\`\`

---
*Updated automatically by orchestrator*"
}
```

### Progress Display (Posted to Tracking Issue)

```markdown
## Orchestration Status

**ID:** orch-2025-12-02-001
**Scope:** Milestone v1.0.0
**Updated:** 2025-12-02T14:30:00Z

### Issue Status

| Status | Issues |
|--------|--------|
| Pending | #149, #150, #151 |
| In Progress | (see below) |
| Awaiting Dependencies | #146 |
| Blocked | #148 |
| Completed | #135, #136, #137, #138, #139, #140, #141, #147 |

### Active Workers

| Issue | Title |
|-------|-------|
| #142 | Add dark mode toggle |
| #143 | Export functionality |
| #144 | Settings page redesign |
| #145 | API rate limiting |

### Open PRs

| PR | Title | CI Status |
|----|-------|-----------|
| #201 | feat: Dark mode (#142) | PENDING |
| #202 | feat: Export (#143) | SUCCESS |

### Deviation Tracking

Issues waiting on children:

```
#146 → waiting on: #152, #153
```

---
*Updated automatically by orchestrator*
```

## Abort Handling

```markdown
User: STOP

## Aborting Orchestration

1. Signaling workers to save state and exit...
2. Workers completing current operation (max 60s)...
3. Saving orchestration state...
4. Preserving worktrees for inspection...

**State Saved**

Resume: `claude --resume [SESSION_ID]`
Clean up worktrees: `git worktree prune`

**Worker states at abort:**
| Worker | Issue | Status | Can Resume |
|--------|-------|--------|------------|
| w-012 | #142 | Mid-implementation | Yes |
| w-013 | #143 | Testing | Yes |
```

## Rollback (Safety Net)

Auto-merge is enabled with git rollback as the safety net:

```bash
rollback_pr() {
  pr=$1
  merge_commit=$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid')

  if [ -n "$merge_commit" ]; then
    git revert "$merge_commit" --no-edit
    git push

    gh issue comment "$(get_pr_issue "$pr")" --body "## ⚠️ PR Reverted

PR #$pr was automatically reverted due to post-merge issues.

**Reverted commit:** $merge_commit
**Reason:** [REASON]

Issue will be re-queued for another attempt."

    requeue_issue "$(get_pr_issue "$pr")"
  fi
}
```

## Checklist

Before starting orchestration:

- [ ] User typed PROCEED (or UNBOUNDED for unbounded mode)
- [ ] Scope validated (issues exist and are actionable)
- [ ] Git worktrees available (`git worktree list`)
- [ ] GitHub CLI authenticated (`gh auth status`)
- [ ] No uncommitted changes in main worktree
- [ ] Required labels created (`scripts/create-labels.sh`)
- [ ] Tracking issue created with `orchestration-tracking` label

During orchestration:

- [ ] Workers spawned with worktree isolation
- [ ] Worker status tracked via GitHub labels
- [ ] CI status monitored
- [ ] Review artifacts verified before PR merge
- [ ] Failed workers trigger research cycles
- [ ] Handovers happen at turn limit
- [ ] SLEEP entered when only waiting on CI or children
- [ ] Deviation resolution checked each loop
- [ ] Child issues follow full `issue-driven-development` process
- [ ] Status posted to tracking issue

## Review Enforcement

**CRITICAL:** The orchestrator verifies review compliance:

1. Before allowing PR merge:
   - Review artifact exists in issue comments
   - Review status is COMPLETE
   - Unaddressed findings = 0

2. Child issues (from deferred findings):
   - Follow full `issue-driven-development` process
   - Have their own code reviews
   - Cannot skip workflow steps
   - Track via `spawned-from:#N` label

3. Deviation handling:
   - Parent marked `status:awaiting-dependencies`
   - Resumes only when all children closed
   - Orchestrator monitors deviation resolution

## Integration

This skill coordinates:
- `worker-dispatch` - Spawning workers
- `worker-protocol` - Worker behavior (includes review gate)
- `worker-handover` - Context passing
- `ci-monitor` - CI and WAKE handling
- `research-after-failure` - Research cycles
- `issue-driven-development` - Worker follows this (all 13 steps)
- `comprehensive-review` - Workers must complete before PR
- `apply-all-findings` - All findings addressed
- `deferred-finding` - Child issue creation
- `review-gate` - PR creation verification

This skill uses GitHub-native state:
- Issue labels for status tracking
- Issue comments for activity log
- `spawned-from:#N` labels for lineage
- `depth:N` labels for recursion limit
- Tracking issue for orchestration status
