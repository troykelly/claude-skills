---
name: autonomous-orchestration
description: Use when user requests autonomous operation across multiple issues. Orchestrates parallel workers, monitors progress, handles SLEEP/WAKE cycles, and works until scope is complete without user intervention.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Task
  - mcp__github__*
  - mcp__memory__*
model: opus
---

# Autonomous Orchestration

## Overview

Orchestrates long-running autonomous work across multiple issues, spawning parallel workers, monitoring CI, and persisting state across sessions.

**Core principle:** GitHub is the source of truth. Workers are disposable. State survives restarts.

**Announce at start:** "I'm using autonomous-orchestration to work through [SCOPE]. Starting autonomous operation now."

## Prerequisites

- `worker-dispatch` skill for spawning workers
- `worker-protocol` skill for worker behavior
- `ci-monitoring` skill for CI/WAKE handling
- Git worktrees support (workers use isolated worktrees)
- GitHub CLI (`gh`) authenticated
- GitHub Project Board configured

## State Management

**CRITICAL:** All state is stored in GitHub. NO local state files.

| State Store | Purpose | Used For |
|-------------|---------|----------|
| Project Board Status | THE source of truth | Ready, In Progress, In Review, Blocked, Done |
| Issue Comments | Activity log | Worker assignment, progress, deviations |
| Labels | Lineage only | `spawned-from:#N`, `depth:N`, `epic-*` |
| MCP Memory | Fast cache | Read optimization (dual-write pattern) |

**See:** `reference/state-management.md` for detailed state queries and updates.

## Immediate Start (User Consent Implied)

**The user's request for autonomous operation IS their consent.** No additional confirmation required.

When the user requests autonomous work:

1. **Identify scope** - Parse user request for milestone, epic, specific issues, or "all"
2. **Announce intent** - Briefly state what you're about to do
3. **Start immediately** - Begin orchestration without waiting for additional input

```markdown
## Starting Autonomous Operation

**Scope:** [MILESTONE/EPIC/ISSUES or "all open issues"]
**Workers:** Up to 5 parallel
**Mode:** Continuous until complete

Beginning work now...
```

**Do NOT ask for "PROCEED" or any confirmation.** The user asked for autonomous operation - that is the confirmation.

## Automatic Scope Detection

When the user requests autonomous operation without specifying a scope:

### Priority Order

1. **User-specified scope** - If user mentions specific issues, epics, or milestones
2. **Urgent/High Priority standalone issues** - Issues with `priority:urgent` or `priority:high` labels not part of an epic
3. **Epic-based sequential work** - Work through epics in order, completing all issues within each epic
4. **Remaining standalone issues** - Any issues not part of an epic

```bash
detect_work_scope() {
  # 1. Check for urgent/high priority standalone issues first
  PRIORITY_ISSUES=$(gh issue list --state open \
    --label "priority:urgent,priority:high" \
    --json number,labels \
    --jq '[.[] | select(.labels | map(.name) | any(startswith("epic-")) | not)] | .[].number')

  if [ -n "$PRIORITY_ISSUES" ]; then
    echo "priority_standalone"
    echo "$PRIORITY_ISSUES"
    return
  fi

  # 2. Get epics in order (by creation date)
  EPICS=$(gh issue list --state open --label "type:epic" \
    --json number,title,createdAt \
    --jq 'sort_by(.createdAt) | .[].number')

  if [ -n "$EPICS" ]; then
    echo "epics"
    echo "$EPICS"
    return
  fi

  # 3. Fall back to all open issues
  ALL_ISSUES=$(gh issue list --state open --json number --jq '.[].number')
  echo "all_issues"
  echo "$ALL_ISSUES"
}
```

## Continuous Operation Until Complete

Autonomous operation continues until ALL of:
- No open issues remain in scope
- No open PRs awaiting merge
- No issues in "In Progress" or "In Review" status

The operation does NOT pause for:
- Progress updates
- Confirmation between issues
- Switching between epics
- Any user input (unless blocked by a fatal error)

## Orchestration Loop

```
┌──────────────────────────────────────────────────────────┐
│                       MAIN LOOP                          │
└─────────────────────────┬────────────────────────────────┘
                          │
      ┌───────────────────┼───────────────────┐
      ▼                   ▼                   ▼
┌───────────┐      ┌───────────┐      ┌───────────┐
│ CHECK     │      │ CHECK     │      │ SPAWN     │
│ WORKERS   │      │ CI/PRs    │      │ WORKERS   │
└─────┬─────┘      └─────┬─────┘      └─────┬─────┘
      │                  │                  │
      └──────────────────┼──────────────────┘
                         │
                         ▼
               ┌───────────────────┐
               │ EVALUATE STATE    │
               │                   │
               │ All done? → Exit  │
               │ Waiting? → SLEEP  │
               │ Work? → Continue  │
               └───────────────────┘
```

**See:** `reference/loop-implementation.md` for full loop code.

### Loop Steps

1. **Check Deviation Resolution** - Resume issues whose children are all closed
2. **Check CI/PRs** - Monitor for merge readiness, verify review artifacts
3. **Spawn Workers** - Up to 5 parallel workers from Ready queue
4. **Evaluate State** - Determine next action (continue, sleep, complete)
5. **Brief Pause** - 30 second interval between iterations

## Scope Types

### Milestone

```bash
gh issue list --milestone "v1.0.0" --state open --json number --jq '.[].number'
```

### Epic

```bash
gh issue list --label "epic-dark-mode" --state open --json number --jq '.[].number'
```

### Unbounded (All Open Issues)

```bash
gh issue list --state open --json number --jq '.[].number'
```

**Do NOT ask for "UNBOUNDED" confirmation.** The user's request is their consent.

## Failure Handling

Workers that fail do NOT immediately become blocked:

```
Attempt 1 → Research → Attempt 2 → Research → Attempt 3 → Research → Attempt 4 → BLOCKED
```

Only after 3+ research cycles is an issue marked as blocked.

**See:** `reference/failure-recovery.md` for research cycle implementation.

### Blocked Determination

An issue is only marked blocked when:
- Multiple research cycles completed (3+)
- Research concludes "impossible without external input"
- Examples: missing credentials, requires human decision, external service down

## SLEEP/WAKE

### Entering SLEEP

Orchestration sleeps when:
- All issues are either blocked or in review
- No work can proceed without external event

State is posted to GitHub tracking issue (survives crashes).

### WAKE Mechanisms

- **SessionStart hook** - Checks CI status on new Claude session
- **Manual** - `claude --resume [SESSION_ID]`

## Checklist

Before starting orchestration:

- [ ] Scope identified (explicit or auto-detected)
- [ ] Git worktrees available (`git worktree list`)
- [ ] GitHub CLI authenticated (`gh auth status`)
- [ ] No uncommitted changes in main worktree
- [ ] Tracking issue exists with `orchestration-tracking` label
- [ ] Project board configured with Status field

During orchestration:

- [ ] Workers spawned with worktree isolation
- [ ] Worker status tracked via Project Board (NOT labels)
- [ ] CI status monitored
- [ ] Review artifacts verified before PR merge
- [ ] Failed workers trigger research cycles
- [ ] Handovers happen at turn limit
- [ ] SLEEP entered when only waiting on CI
- [ ] Deviation resolution checked each loop
- [ ] Status posted to tracking issue

## Review Enforcement

**CRITICAL:** The orchestrator verifies review compliance:

1. **Before PR merge:**
   - Review artifact exists in issue comments
   - Review status is COMPLETE
   - Unaddressed findings = 0

2. **Child issues (from deferred findings):**
   - Follow full `issue-driven-development` process
   - Have their own code reviews
   - Track via `spawned-from:#N` label

3. **Deviation handling:**
   - Parent status set to Blocked on project board
   - Resumes only when all children closed

## Integration

This skill coordinates:

| Skill | Purpose |
|-------|---------|
| `worker-dispatch` | Spawning workers |
| `worker-protocol` | Worker behavior |
| `worker-handover` | Context passing |
| `ci-monitoring` | CI and WAKE handling |
| `research-after-failure` | Research cycles |
| `issue-driven-development` | Worker follows this |
| `comprehensive-review` | Workers must complete before PR |
| `project-board-enforcement` | ALL state queries and updates |

## Reference Files

- `reference/state-management.md` - State queries, updates, deviation handling
- `reference/loop-implementation.md` - Full loop code and helpers
- `reference/failure-recovery.md` - Research cycles, blocked handling, SLEEP/WAKE
