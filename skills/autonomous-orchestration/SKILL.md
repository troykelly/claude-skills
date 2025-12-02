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

## State Management

### Directory Structure

```
.orchestrator/
├── state.json           # Orchestration state
├── workers.json         # Active worker tracking
├── history.jsonl        # Append-only activity log
├── logs/
│   └── worker-*.log     # Worker output logs
├── pids/
│   └── worker-*.pid     # Worker process IDs
└── worktrees/           # Git worktree references
```

### state.json

```json
{
  "orchestration_id": "orch-2025-12-02-001",
  "mode": "active",
  "scope": {
    "type": "milestone",
    "target": "v1.0.0",
    "issues": [123, 124, 125, 126, 127]
  },
  "settings": {
    "max_parallel_workers": 5,
    "max_turns_per_worker": 100,
    "auto_merge": true,
    "wake_poll_interval_seconds": 300,
    "wake_webhook_port": null,
    "unbounded": false
  },
  "queue": {
    "pending": [126, 127],
    "in_progress": [123, 124, 125],
    "blocked": [],
    "completed": []
  },
  "sleep": {
    "sleeping": false,
    "reason": null,
    "since": null,
    "waiting_on": []
  },
  "stats": {
    "workers_spawned": 12,
    "handovers": 3,
    "issues_completed": 8,
    "prs_merged": 7,
    "research_cycles": 2
  },
  "started": "2025-12-02T10:00:00Z",
  "last_activity": "2025-12-02T14:30:00Z",
  "resume_session": "session-abc123"
}
```

### workers.json

```json
{
  "workers": [
    {
      "id": "worker-abc123",
      "pid": 12345,
      "issue": 123,
      "worktree": "../project-worker-123",
      "branch": "feature/123-dark-mode",
      "started": "2025-12-02T14:00:00Z",
      "turns_used": 45,
      "status": "running",
      "attempt": 1,
      "research_cycles": 0,
      "log_file": ".orchestrator/logs/worker-abc123.log",
      "handover_from": null
    }
  ],
  "max_worker_id": 15
}
```

### history.jsonl (Append-Only)

```json
{"ts":"2025-12-02T10:00:00Z","event":"orchestration_started","scope":"milestone:v1.0.0"}
{"ts":"2025-12-02T10:01:00Z","event":"worker_spawned","worker":"worker-001","issue":123}
{"ts":"2025-12-02T10:45:00Z","event":"worker_completed","worker":"worker-001","issue":123,"pr":201}
{"ts":"2025-12-02T10:46:00Z","event":"ci_started","pr":201}
{"ts":"2025-12-02T11:00:00Z","event":"sleep_started","reason":"waiting_for_ci","prs":[201]}
{"ts":"2025-12-02T11:15:00Z","event":"wake_triggered","trigger":"ci_complete"}
{"ts":"2025-12-02T11:16:00Z","event":"pr_merged","pr":201,"issue":123}
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

### Loop Implementation

```bash
# Initialize orchestration
mkdir -p .orchestrator/{logs,pids,worktrees}

while true; do
  log_activity "loop_iteration"

  # ─────────────────────────────────────────────────────────────
  # 1. CHECK WORKERS
  # ─────────────────────────────────────────────────────────────
  for worker in $(get_active_workers); do
    pid=$(cat ".orchestrator/pids/$worker.pid" 2>/dev/null)

    if ! kill -0 "$pid" 2>/dev/null; then
      # Worker exited
      exit_status=$(get_worker_exit_status "$worker")

      case "$exit_status" in
        "completed")
          mark_issue_pr_created "$worker"
          cleanup_worker "$worker"
          ;;
        "handover_needed")
          # Hit 100 turns, needs replacement
          spawn_replacement_worker "$worker"
          ;;
        "needs_research")
          # Failed, trigger research cycle
          trigger_research_cycle "$worker"
          ;;
        "blocked")
          # Truly blocked, mark and move on
          mark_issue_blocked "$worker"
          cleanup_worker "$worker"
          ;;
      esac
    fi
  done

  # ─────────────────────────────────────────────────────────────
  # 2. CHECK CI/PRs
  # ─────────────────────────────────────────────────────────────
  for pr in $(get_open_prs); do
    ci_status=$(gh pr checks "$pr" --json state,name --jq '.')

    if all_checks_passed "$ci_status"; then
      if [ "$AUTO_MERGE" = "true" ]; then
        gh pr merge "$pr" --squash --auto
        log_activity "pr_merged" "$pr"
      else
        log_activity "pr_ready" "$pr"
      fi
    elif any_check_failed "$ci_status"; then
      handle_ci_failure "$pr"
    fi
  done

  # ─────────────────────────────────────────────────────────────
  # 3. SPAWN NEW WORKERS
  # ─────────────────────────────────────────────────────────────
  active_count=$(count_active_workers)

  while [ "$active_count" -lt 5 ]; do
    next_issue=$(get_next_pending_issue)

    if [ -z "$next_issue" ]; then
      break  # No more issues to work
    fi

    spawn_worker "$next_issue"
    active_count=$((active_count + 1))
  done

  # ─────────────────────────────────────────────────────────────
  # 4. EVALUATE STATE
  # ─────────────────────────────────────────────────────────────
  pending=$(count_pending_issues)
  in_progress=$(count_active_workers)
  waiting_ci=$(count_prs_in_ci)

  if [ "$pending" -eq 0 ] && [ "$in_progress" -eq 0 ] && [ "$waiting_ci" -eq 0 ]; then
    # All done!
    complete_orchestration
    exit 0
  fi

  if [ "$in_progress" -eq 0 ] && [ "$waiting_ci" -gt 0 ]; then
    # Nothing to do but wait for CI
    enter_sleep "waiting_for_ci"
    exit 0  # Will be woken by wake mechanism
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

  # Update state
  jq --arg reason "$reason" \
     --arg since "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.sleep.sleeping = true | .sleep.reason = $reason | .sleep.since = $since' \
     .orchestrator/state.json > .orchestrator/state.json.tmp
  mv .orchestrator/state.json.tmp .orchestrator/state.json

  # Get PRs we're waiting on
  waiting_prs=$(get_prs_in_ci)
  jq --argjson prs "$waiting_prs" '.sleep.waiting_on = $prs' \
     .orchestrator/state.json > .orchestrator/state.json.tmp
  mv .orchestrator/state.json.tmp .orchestrator/state.json

  # Log
  log_activity "sleep_started" "$reason"

  # Report to user
  echo "## Orchestration Sleeping"
  echo ""
  echo "**Reason:** $reason"
  echo "**Waiting on:** $(echo $waiting_prs | jq -r 'join(", ")')"
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

## Status Reporting

### Progress Display

```markdown
## Orchestration Status

**ID:** orch-2025-12-02-001
**Mode:** Active
**Scope:** Milestone v1.0.0

### Progress
████████████░░░░░░░░ 60% (9/15)

### Active Workers (4/5)
| Worker | Issue | Branch | Turns | Status |
|--------|-------|--------|-------|--------|
| w-012 | #142 | feature/142-dark-mode | 45/100 | Implementing |
| w-013 | #143 | feature/143-export | 78/100 | Testing |
| w-014 | #144 | feature/144-settings | 12/100 | Starting |
| w-015 | #145 | feature/145-api | 91/100 | Near handover |

### CI Queue (2)
| PR | Issue | Checks | Status |
|----|-------|--------|--------|
| #201 | #140 | 16/18 | Running |
| #202 | #141 | 18/18 | ✅ Merging |

### Completed (9)
✅ #135, #136, #137, #138, #139, #140, #141, #146, #147

### Blocked (1)
🚫 #148 - Requires API credentials (research cycles: 3)

### Queue (3)
⏳ #149, #150, #151

### Stats
| Metric | Value |
|--------|-------|
| Workers spawned | 18 |
| Handovers | 4 |
| Research cycles | 3 |
| PRs merged | 8 |
| Runtime | 2h 34m |
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
- [ ] `.orchestrator/` directory created
- [ ] Initial state.json written

During orchestration:

- [ ] Workers spawned with worktree isolation
- [ ] Worker status checked every loop
- [ ] CI status monitored
- [ ] Failed workers trigger research cycles
- [ ] Handovers happen at turn limit
- [ ] SLEEP entered when only waiting on CI
- [ ] State persisted after every change

## Integration

This skill coordinates:
- `worker-dispatch` - Spawning workers
- `worker-protocol` - Worker behavior
- `worker-handover` - Context passing
- `ci-monitor` - CI and WAKE handling
- `research-after-failure` - Research cycles
- `issue-driven-development` - Worker follows this
