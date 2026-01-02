# Failure Handling and Recovery

## Retry with Research

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

## Research Cycle Implementation

Research workers are spawned with read-only tools to investigate failures:

```bash
trigger_research_cycle() {
  worker=$1
  issue=$(get_worker_issue "$worker")
  cycle=$(get_research_cycle_count "$issue")

  # Spawn research worker (read-only tools)
  # Research context is posted to the issue as a comment
  claude -p "$(cat <<PROMPT
You are a research agent investigating why issue #$issue is failing.

## Research Cycle: $((cycle + 1))

## Previous Attempts
$(get_attempt_history "$issue")

## Your Task
1. Analyze the failure logs
2. Research the problem thoroughly
3. Document findings in issue #$issue as a comment
4. Propose a new approach

## Constraints
- You are READ-ONLY - do not modify code
- Focus on understanding, not fixing
- Be thorough - this is attempt $((cycle + 1))
- Post all findings to the issue comment

Begin by reading the worker logs and issue comments.
PROMPT
)" \
    --allowedTools "Read,Grep,Glob,WebFetch,WebSearch,mcp__memory__*,mcp__github__add_issue_comment" \
    --max-turns 50

  # After research, spawn new worker with research context
  increment_research_cycle "$issue"
  spawn_worker "$issue" --with-research-context
}
```

## Blocked Determination

An issue is only marked blocked when:

1. Multiple research cycles completed (3+)
2. Research concludes "impossible without external input"
3. Examples of true blockers:
   - Missing API credentials
   - Requires decision from human
   - External service unavailable
   - Dependency on unreleased feature

```bash
mark_issue_truly_blocked() {
  issue=$1
  reason=$2

  # Update project board status
  update_project_status "$issue" "Blocked"

  gh issue comment "$issue" --body "## Issue Blocked

**Reason:** $reason

**Attempts:** $(get_attempt_count "$issue")
**Research Cycles:** $(get_research_cycle_count "$issue")

**Why Blocked:**
This issue cannot proceed without external intervention.

**Required Action:**
$reason

---
*Orchestration ID: $ORCHESTRATION_ID*"
}
```

## Git Worktree Isolation

Workers use separate git worktrees to avoid conflicts:

```bash
create_worker_worktree() {
  issue=$1
  worker_id=$2
  branch="feature/$issue-$(slugify_issue_title "$issue")"
  worktree_path="../$(basename $PWD)-worker-$issue"

  git branch "$branch" 2>/dev/null || true
  git worktree add "$worktree_path" "$branch"

  echo "$worktree_path"
}

cleanup_worker_worktree() {
  worktree_path=$1

  git worktree remove "$worktree_path" --force
  git worktree prune
}
```

## SLEEP/WAKE

### Entering SLEEP

State is posted to GitHub tracking issue (survives crashes):

```bash
enter_sleep() {
  reason=$1

  TRACKING_ISSUE=$(gh issue list --label "orchestration-tracking" --json number --jq '.[0].number')
  WAITING_PRS=$(gh pr list --json number --jq '[.[].number] | join(", ")')

  gh issue comment "$TRACKING_ISSUE" --body "## Orchestration Sleeping

**Reason:** $reason
**Since:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Waiting On

| Type | Items |
|------|-------|
| PRs in CI | $WAITING_PRS |

### Wake Mechanisms

- **SessionStart hook:** Checks CI status on new session
- **Manual:** \`claude --resume $RESUME_SESSION\`

---
*Orchestrator: $ORCHESTRATION_ID*"

  echo "## Orchestration Sleeping"
  echo "**Reason:** $reason"
  echo "**Waiting on PRs:** $WAITING_PRS"
}
```

### WAKE Mechanisms

See `ci-monitoring` skill for detailed WAKE implementations:
- SessionStart hook checks CI status
- Manual resume with session ID

## Abort Handling

```markdown
User: STOP

## Aborting Orchestration

1. Signaling workers to save state and exit...
2. Workers completing current operation (max 60s)...
3. Saving orchestration state to GitHub...
4. Preserving worktrees for inspection...

**State Saved to GitHub**

Resume: `claude --resume [SESSION_ID]`
Clean up worktrees: `git worktree prune`

**Worker states at abort:**
| Worker | Issue | Status | Can Resume |
|--------|-------|--------|------------|
| w-012 | #142 | Mid-implementation | Yes |
| w-013 | #143 | Testing | Yes |
```

## Rollback (Safety Net)

Auto-merge with git rollback as safety net:

```bash
rollback_pr() {
  pr=$1
  merge_commit=$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid')

  if [ -n "$merge_commit" ]; then
    git revert "$merge_commit" --no-edit
    git push

    ISSUE=$(get_pr_issue "$pr")
    gh issue comment "$ISSUE" --body "## PR Reverted

PR #$pr was automatically reverted due to post-merge issues.

**Reverted commit:** $merge_commit
**Reason:** [REASON]

Issue will be re-queued for another attempt."

    # Re-queue via project board
    update_project_status "$ISSUE" "Ready"
  fi
}
```
