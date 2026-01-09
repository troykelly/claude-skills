---
name: worker-dispatch
description: Use to spawn isolated worker processes for autonomous issue work. Uses Task tool with run_in_background for parallel execution and TaskOutput for monitoring.
allowed-tools:
  - Bash
  - Read
  - Task
  - TaskOutput
  - mcp__github__*
  - mcp__memory__*
model: opus
---

# Worker Dispatch

## Overview

Spawns and manages worker Claude agents using the **Task tool with `run_in_background: true`**. Workers run as parallel background agents monitored via **TaskOutput**.

**Core principle:** Workers are isolated, scoped, and expendable. State lives in GitHub, not in workers.

**Announce at start:** "I'm using worker-dispatch to spawn a worker for issue #[N]."

## State Management

**CRITICAL:** Worker state is stored in GitHub. Task IDs are ephemeral orchestration state.

| State | Location | Purpose |
|-------|----------|---------|
| Worker assignment | Issue comment | Who is working on what |
| Worker status | Project Board | In Progress, Done, etc. |
| Task IDs | Orchestrator memory | Monitor running agents |
| Agent output | TaskOutput tool | Check progress and results |

Task IDs exist only for the current orchestration session. All persistent state is in GitHub.

## Worker Architecture

```
Main Repository (./)
│
└── Worktrees (parallel directories)
    │
    ├── ../project-worker-123/    ← Worker for issue #123
    │   └── (full repo copy on feature/123-* branch)
    │
    ├── ../project-worker-124/    ← Worker for issue #124
    │   └── (full repo copy on feature/124-* branch)
    │
    └── ../project-worker-125/    ← Worker for issue #125
        └── (full repo copy on feature/125-* branch)
```

## Spawning a Worker

### Step 1: Create Worktree

```bash
spawn_worker() {
  issue=$1
  context_file=$2  # Optional: handover context

  worker_id="worker-$(date +%s)-$issue"

  issue_title=$(gh issue view "$issue" --json title --jq '.title' | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | \
    cut -c1-40)

  branch="feature/$issue-$issue_title"
  worktree_path="../$(basename $PWD)-worker-$issue"

  git fetch origin main
  git branch "$branch" origin/main 2>/dev/null || true
  git worktree add "$worktree_path" "$branch"

  echo "Created worktree: $worktree_path on branch $branch"
}
```

### Step 2: Register Worker in GitHub

Post worker assignment to the issue as a structured comment:

```bash
register_worker() {
  worker_id=$1
  issue=$2
  worktree=$3

  # Post assignment comment with structured marker
  gh issue comment "$issue" --body "<!-- WORKER:ASSIGNED -->
\`\`\`json
{
  \"assigned\": true,
  \"worker_id\": \"$worker_id\",
  \"assigned_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
  \"worktree\": \"$worktree\"
}
\`\`\`
<!-- /WORKER:ASSIGNED -->

**Worker Assigned**
- **Worker ID:** \`$worker_id\`
- **Started:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Worktree:** \`$worktree\`

---
*Orchestrator: $ORCHESTRATION_ID*"

  # Update project board status
  update_project_status "$issue" "In Progress"
}
```

### Step 3: Construct Worker Prompt

```bash
construct_worker_prompt() {
  issue=$1
  worker_id=$2
  context_file=$3
  attempt=$4
  research_context=$5

  cat <<PROMPT
You are a worker agent. Your ONLY task is to complete GitHub issue #$issue.

## Worker Identity
- **Worker ID:** $worker_id
- **Issue:** #$issue
- **Attempt:** $attempt
- **Orchestration:** $ORCHESTRATION_ID

## Your Mission
Complete issue #$issue by following the issue-driven-development workflow:
1. Read and understand the issue completely
2. Create/verify you're on the correct branch
3. Implement the solution with TDD
4. Run all tests
5. Create a PR when complete
6. Update issue with progress comments throughout

## Constraints
- Work ONLY on issue #$issue - no other issues
- Do NOT modify unrelated code
- Do NOT start other work
- Follow all project skills (strict-typing, ipv6-first, etc.)
- Maximum 100 turns - if approaching limit, prepare handover

## Exit Conditions
Exit when ANY of these occur:
1. **PR Created** - Your work is complete
2. **Blocked** - You cannot proceed without external input
3. **Turns Exhausted** - Approaching 100 turns, handover needed
4. **Failed** - Tests fail after good-faith effort (triggers research)

## Progress Reporting
Update the issue with comments as you work.

## On Completion
Post completion comment to the issue.

## On Handover Needed
Post handover context to the issue comment (NOT local file).

$(if [ -n "$context_file" ] && [ -f "$context_file" ]; then
  echo "## Context from Previous Worker"
  cat "$context_file"
fi)

$(if [ -n "$research_context" ]; then
  echo "## Research Context (Previous Failures)"
  echo "$research_context"
fi)

## Begin
Start by reading issue #$issue to understand the requirements.
PROMPT
}
```

### Step 4: Spawn Worker Agent

Use the **Task tool** with `run_in_background: true` to spawn a parallel worker agent:

```
Task(
  description: "Issue #[ISSUE] worker",
  prompt: [WORKER_PROMPT],
  subagent_type: "general-purpose",
  run_in_background: true
)
```

**Returns:** A `task_id` (e.g., `aa93f22`) used to monitor the agent.

**Example invocation:**

```markdown
I'm spawning a worker for issue #123.

[Invoke Task tool with:]
- description: "Issue #123 worker"
- prompt: [constructed worker prompt]
- subagent_type: "general-purpose"
- run_in_background: true

Task returns task_id: aa93f22
Storing task_id for monitoring.
```

### Spawning Multiple Workers in Parallel

To spawn multiple workers simultaneously, invoke multiple Task tools in a **single message**:

```markdown
Spawning 3 workers in parallel for issues #123, #124, #125.

[Invoke 3 Task tools in same message:]

Task 1:
- description: "Issue #123 worker"
- prompt: [prompt for #123]
- subagent_type: "general-purpose"
- run_in_background: true

Task 2:
- description: "Issue #124 worker"
- prompt: [prompt for #124]
- subagent_type: "general-purpose"
- run_in_background: true

Task 3:
- description: "Issue #125 worker"
- prompt: [prompt for #125]
- subagent_type: "general-purpose"
- run_in_background: true
```

**CRITICAL:** All Task invocations in the same message start concurrently.

### Complete Spawn Function

```markdown
## Spawning a Worker

1. **Register in GitHub FIRST** (before spawning)
   - Post assignment comment to issue
   - Update project board status to "In Progress"

2. **Construct worker prompt** with:
   - Issue number and context
   - Worker identity
   - Constraints and exit conditions
   - Any handover context from previous attempts

3. **Invoke Task tool:**
   Task(
     description: "Issue #[ISSUE] worker",
     prompt: [WORKER_PROMPT],
     subagent_type: "general-purpose",
     run_in_background: true
   )

4. **Store the returned task_id** for monitoring

5. **Log activity** to tracking issue
```

## Worker Agent Types

Workers are spawned as `general-purpose` subagents by default. The worker prompt defines their behavior and constraints.

| Worker Type | Subagent Type | Purpose |
|-------------|---------------|---------|
| Standard Worker | `general-purpose` | Full implementation with all tools |
| Research Worker | `Explore` | Read-only codebase investigation |
| Review Worker | Custom subagent | Code review without edits |

## Checking Worker Status

Use **TaskOutput** with `block: false` for non-blocking status checks:

```
TaskOutput(
  task_id: "[TASK_ID]",
  block: false,
  timeout: 1000
)
```

### Status Check Pattern

```markdown
## Checking Worker Status

For each active worker task_id:

1. **Invoke TaskOutput (non-blocking):**
   TaskOutput(task_id: "aa93f22", block: false)

2. **Interpret result:**
   - "Task is still running..." → Worker active, continue monitoring
   - Task completed with output → Worker finished, check result

3. **If completed, verify GitHub state:**
   - Check if PR exists: `gh pr list --head "feature/[ISSUE]-*"`
   - Check issue comments for completion/handover/blocked markers
```

### Monitoring Multiple Workers

```markdown
## Monitoring Loop

For each active task_id in [aa93f22, b51e54b, c72f3d1]:

TaskOutput(task_id: "aa93f22", block: false)
TaskOutput(task_id: "b51e54b", block: false)
TaskOutput(task_id: "c72f3d1", block: false)

[All three checks happen in parallel if invoked in same message]

Results:
- aa93f22: "Task is still running..." → Continue monitoring
- b51e54b: Completed → Check GitHub for PR
- c72f3d1: "Task is still running..." → Continue monitoring
```

## Worker Cleanup

When a worker completes (detected via TaskOutput), clean up GitHub state:

```markdown
## Cleanup Steps

1. **Remove task_id from active list** (orchestrator memory)

2. **Post cleanup comment to issue:**
   ```bash
   gh issue comment "$ISSUE" --body "<!-- WORKER:ASSIGNED -->
   \`\`\`json
   {\"assigned\": false, \"cleared_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}
   \`\`\`
   <!-- /WORKER:ASSIGNED -->

   **Worker Completed**
   - **Task ID:** \`[TASK_ID]\`
   - **Cleared:** [TIMESTAMP]
   - **Result:** [COMPLETED|BLOCKED|HANDOVER]"
   ```

3. **Update project board** based on result:
   - PR created → "In Review"
   - Blocked → "Blocked"
   - Handover needed → Keep "In Progress", spawn replacement
```

## Replacement Worker (After Handover)

When a worker signals handover needed:

```markdown
## Spawning Replacement

1. **Get handover context from issue comments:**
   ```bash
   gh api "/repos/$OWNER/$REPO/issues/$ISSUE/comments" \
     --jq '[.[] | select(.body | contains("<!-- HANDOVER:START -->"))] | last | .body'
   ```

2. **Construct new prompt** including handover context

3. **Spawn replacement with Task tool:**
   Task(
     description: "Issue #[ISSUE] worker (attempt [N])",
     prompt: [PROMPT_WITH_HANDOVER_CONTEXT],
     subagent_type: "general-purpose",
     run_in_background: true
   )

4. **Store new task_id**, remove old task_id from active list
```

## Parallel Dispatch

Dispatch multiple workers in a single message for true parallelism:

```markdown
## Dispatching Available Slots

1. **Count current workers:**
   - Query project board for "In Progress" items
   - max_workers = 5
   - available = max_workers - current

2. **Get pending issues:**
   - Query project board for "Ready" items
   - Take up to `available` issues

3. **Dispatch all in ONE message:**

   [For 3 available slots with issues #123, #124, #125:]

   Task(description: "Issue #123 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)
   Task(description: "Issue #124 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)
   Task(description: "Issue #125 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)

4. **Store all returned task_ids** for monitoring

**CRITICAL:** Invoke all Task tools in the SAME message for concurrent execution.
```

## PR Workers

PR workers have a different lifecycle than issue workers. They resolve existing PRs rather than implementing new features.

### PR Worker vs Issue Worker

| Aspect | Issue Worker | PR Worker |
|--------|--------------|-----------|
| Goal | Implement feature, create PR | Resolve existing PR |
| Branch | Creates new feature branch | Checks out existing PR branch |
| Worktree | `../project-worker-[ISSUE]` | `../project-pr-[PR_NUMBER]` |
| Registration | Posts to issue | Posts to PR |
| Exit condition | PR created | PR merged or blocked |

### Spawning a PR Worker

```bash
spawn_pr_worker() {
  pr=$1

  # Get PR details
  PR_JSON=$(gh pr view "$pr" --json number,headRefName,title)
  PR_BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName')

  worker_id="pr-worker-$(date +%s)-$pr"
  worktree_path="../$(basename $PWD)-pr-$pr"

  # Create worktree from the PR's branch
  git fetch origin "$PR_BRANCH"
  git worktree add "$worktree_path" "origin/$PR_BRANCH"

  echo "Created PR worktree: $worktree_path on branch $PR_BRANCH"
}
```

### PR Worker Prompt Template

```bash
construct_pr_worker_prompt() {
  pr=$1
  worker_id=$2
  worktree_path=$3

  cat <<PROMPT
You are a PR resolution worker. Your task is to resolve PR #$pr.

## Worker Identity
- **Worker ID:** $worker_id
- **PR:** #$pr
- **Worktree:** $worktree_path

## Your Mission
Resolve PR #$pr through its full lifecycle:

1. **Check CI Status** - \`gh pr checks $pr\`
   - If ANY check is failing: investigate logs, fix code, push, wait for green
   - Continue fixing until ALL checks pass

2. **Verify Review Artifact** - Check linked issue for review comment
   - Look for structured review (<!-- REVIEW:START --> markers)
   - If missing: perform comprehensive code review and post artifact

3. **Check Merge Eligibility**
   - Check for 'do-not-merge' label → Skip merge, report blocked
   - Check for comments blocking merge → Skip merge, report blocked
   - If merge is permitted: \`gh pr merge $pr --squash --delete-branch\`

4. **Report Result**
   - Post completion comment to PR
   - Update linked issue status if applicable

## Constraints
- Only fix code directly related to CI failures
- Always push to the existing PR branch (do not create new branches)
- Use 'gh pr merge' with --squash --delete-branch

## Exit Conditions
Exit when ANY of these occur:
1. **PR Merged** - Resolution complete
2. **Blocked** - Cannot proceed (label, comment, or external dependency)
3. **Turns Exhausted** - Approaching 100 turns, prepare handover

## Begin
Start by checking CI status: \`gh pr checks $pr\`
PROMPT
}
```

### Spawning Multiple PR Workers

```markdown
## Dispatching PR Workers

1. **Get actionable PRs:**
   - Exclude release/* branches
   - Exclude release-placeholder label
   - Exclude do-not-merge label

2. **Create worktrees for each PR**

3. **Dispatch all in ONE message:**

   Task(description: "PR #123 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)
   Task(description: "PR #124 worker", prompt: [...], subagent_type: "general-purpose", run_in_background: true)

4. **Store task_ids** for monitoring
```

### PR Worker Cleanup

```bash
cleanup_pr_worker() {
  pr=$1
  worktree_path=$2
  result=$3  # MERGED or BLOCKED

  # Post result comment to PR
  gh pr comment "$pr" --body "## PR Worker Complete

**Result:** $result
**Worker ID:** $worker_id
**Completed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

---
*Orchestrator*"

  # Remove worktree
  git worktree remove "$worktree_path" --force 2>/dev/null || true
}
```

## Checklist

When spawning a worker:

- [ ] Worker registered in GitHub (issue comment)
- [ ] Project board status updated to In Progress
- [ ] Worker prompt constructed with all context
- [ ] Task tool invoked with `run_in_background: true`
- [ ] Returned task_id stored for monitoring
- [ ] Activity logged to tracking issue

When monitoring workers:

- [ ] TaskOutput invoked with `block: false`
- [ ] Multiple TaskOutput calls in same message for parallelism
- [ ] Completed workers detected and handled
- [ ] GitHub state verified (PR exists, comments checked)

When cleaning up:

- [ ] Task_id removed from active list
- [ ] Cleanup comment posted to issue
- [ ] Project board status updated
- [ ] Activity logged

When spawning a PR worker:

- [ ] PR worktree created from PR branch
- [ ] PR worker prompt constructed
- [ ] Task tool invoked with `run_in_background: true`
- [ ] Returned task_id stored for monitoring

When PR worker completes:

- [ ] Task_id removed from active list
- [ ] Result comment posted to PR
- [ ] Worktree cleaned up
- [ ] Activity logged

## Integration

This skill is used by:
- `autonomous-orchestration` - Main orchestration loop
- `claude-autonomous --pr` - PR resolution mode

This skill uses:
- `worker-protocol` - Behavior injected into prompts
- `worker-handover` - Handover context format
- `ci-monitoring` - CI failure investigation (for PR workers)
