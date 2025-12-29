---
name: worker-dispatch
description: Use to spawn isolated worker processes for autonomous issue work. Creates git worktrees, constructs worker prompts, manages PIDs, and handles worker lifecycle.
---

# Worker Dispatch

## Overview

Spawns and manages worker Claude processes in isolated git worktrees. Workers are disposable - if they fail, spawn another.

**Core principle:** Workers are isolated, scoped, and expendable. State lives in GitHub, not in workers.

**Announce at start:** "I'm using worker-dispatch to spawn a worker for issue #[N]."

## Worker Architecture

```
Main Repository (./)
│
├── .orchestrator/
│   ├── logs/worker-*.log
│   ├── pids/worker-*.pid
│   └── state.json
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

  # Generate worker ID
  worker_id="worker-$(date +%s)-$issue"

  # Get issue title for branch name
  issue_title=$(gh issue view "$issue" --json title --jq '.title' | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | \
    cut -c1-40)

  branch="feature/$issue-$issue_title"
  worktree_path="../$(basename $PWD)-worker-$issue"

  # Create branch from main if not exists
  git fetch origin main
  git branch "$branch" origin/main 2>/dev/null || true

  # Create worktree
  git worktree add "$worktree_path" "$branch"

  echo "Created worktree: $worktree_path on branch $branch"
}
```

### Step 2: Construct Worker Prompt

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
Exit (allow process to end) when ANY of these occur:
1. **PR Created** - Your work is complete
2. **Blocked** - You cannot proceed without external input
3. **Turns Exhausted** - Approaching 100 turns, handover needed
4. **Failed** - Tests fail after good-faith effort (triggers research)

## Progress Reporting
Update the issue with comments as you work:
\`\`\`
🤖 **Worker $worker_id - Update**
**Status:** [Starting|Implementing|Testing|PR Created|Blocked]
**Progress:** [What you've done]
**Next:** [What's next]
\`\`\`

## On Completion
When creating PR, use this format:
\`\`\`
🤖 **Worker Complete**
**PR:** #[PR_NUMBER]
**Issue:** #$issue
**Worker:** $worker_id
\`\`\`

## On Handover Needed (Approaching Turn Limit)
Create handover file BEFORE exiting:
\`\`\`
🤖 **Worker Handover Needed**
**Turns Used:** [N]/100
**Handover File:** .orchestrator/handover-$issue.md
\`\`\`

$(if [ -n "$context_file" ] && [ -f "$context_file" ]; then
  echo "## Context from Previous Worker"
  echo ""
  cat "$context_file"
  echo ""
fi)

$(if [ -n "$research_context" ]; then
  echo "## Research Context (Previous Failures)"
  echo ""
  echo "$research_context"
  echo ""
fi)

## Begin
Start by reading issue #$issue to understand the requirements.
PROMPT
}
```

### Step 3: Spawn Process

```bash
spawn_worker_process() {
  issue=$1
  worker_id=$2
  worktree_path=$3
  prompt=$4

  log_file=".orchestrator/logs/$worker_id.log"
  pid_file=".orchestrator/pids/$worker_id.pid"

  # Spawn worker in worktree directory
  (
    cd "$worktree_path"
    claude -p "$prompt" \
      --allowedTools "Bash,Read,Edit,Write,Grep,Glob,mcp__git__*,mcp__memory__*,WebFetch,WebSearch" \
      --max-turns 100 \
      --permission-mode acceptEdits \
      --output-format json \
      2>&1
  ) > "$log_file" &

  worker_pid=$!
  echo "$worker_pid" > "$pid_file"

  # Register worker
  register_worker "$worker_id" "$worker_pid" "$issue" "$worktree_path"

  echo "Spawned worker $worker_id (PID: $worker_pid) for issue #$issue"
}
```

### Complete Spawn Function

```bash
spawn_worker() {
  issue=$1
  context_file=${2:-""}
  attempt=${3:-1}
  research_context=${4:-""}

  # Generate worker ID
  worker_id="worker-$(date +%s)-$issue"

  # Create worktree
  worktree_path=$(create_worktree "$issue" "$worker_id")

  # Construct prompt
  prompt=$(construct_worker_prompt "$issue" "$worker_id" "$context_file" "$attempt" "$research_context")

  # Spawn process
  spawn_worker_process "$issue" "$worker_id" "$worktree_path" "$prompt"

  # Update orchestration state
  add_to_in_progress "$issue"
  remove_from_pending "$issue"

  # Log activity
  log_activity "worker_spawned" "$worker_id" "$issue"
}
```

## Tool Scoping

### Standard Worker (Full Implementation)

```bash
--allowedTools "Bash,Read,Edit,Write,Grep,Glob,mcp__git__*,mcp__memory__*,WebFetch,WebSearch"
```

### Research Worker (Read-Only)

```bash
--allowedTools "Read,Grep,Glob,WebFetch,WebSearch,mcp__memory__*"
```

### Review Worker (No Edits)

```bash
--allowedTools "Read,Grep,Glob,Bash(pnpm test:*),Bash(pnpm lint:*)"
```

## Worker Registration

```bash
register_worker() {
  worker_id=$1
  pid=$2
  issue=$3
  worktree=$4

  # Add to workers.json
  jq --arg id "$worker_id" \
     --arg pid "$pid" \
     --arg issue "$issue" \
     --arg worktree "$worktree" \
     --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.workers += [{
       id: $id,
       pid: ($pid | tonumber),
       issue: ($issue | tonumber),
       worktree: $worktree,
       started: $started,
       turns_used: 0,
       status: "running",
       attempt: 1,
       research_cycles: 0,
       log_file: ".orchestrator/logs/\($id).log",
       handover_from: null
     }]' .orchestrator/workers.json > .orchestrator/workers.json.tmp
  mv .orchestrator/workers.json.tmp .orchestrator/workers.json
}
```

## Checking Worker Status

```bash
check_worker_status() {
  worker_id=$1

  pid=$(jq -r --arg id "$worker_id" '.workers[] | select(.id == $id) | .pid' .orchestrator/workers.json)

  if ! kill -0 "$pid" 2>/dev/null; then
    # Process exited - determine why
    log_file=".orchestrator/logs/$worker_id.log"

    if grep -q '"pr_created":' "$log_file"; then
      echo "completed"
    elif grep -q 'handover_needed' "$log_file"; then
      echo "handover_needed"
    elif grep -q '"blocked":' "$log_file"; then
      echo "blocked"
    elif grep -q '"error":' "$log_file"; then
      echo "failed"
    else
      echo "unknown"
    fi
  else
    echo "running"
  fi
}
```

## Worker Cleanup

```bash
cleanup_worker() {
  worker_id=$1
  keep_worktree=${2:-false}

  # Get worker info
  worker=$(jq --arg id "$worker_id" '.workers[] | select(.id == $id)' .orchestrator/workers.json)
  worktree=$(echo "$worker" | jq -r '.worktree')
  issue=$(echo "$worker" | jq -r '.issue')

  # Remove worktree (unless keeping for inspection)
  if [ "$keep_worktree" = "false" ] && [ -d "$worktree" ]; then
    git worktree remove "$worktree" --force 2>/dev/null || true
    git worktree prune
  fi

  # Remove from workers.json
  jq --arg id "$worker_id" '.workers = [.workers[] | select(.id != $id)]' \
    .orchestrator/workers.json > .orchestrator/workers.json.tmp
  mv .orchestrator/workers.json.tmp .orchestrator/workers.json

  # Clean up PID file
  rm -f ".orchestrator/pids/$worker_id.pid"

  log_activity "worker_cleaned" "$worker_id" "$issue"
}
```

## Replacement Worker (After Handover)

```bash
spawn_replacement_worker() {
  old_worker_id=$1

  # Get old worker info
  old_worker=$(jq --arg id "$old_worker_id" '.workers[] | select(.id == $id)' .orchestrator/workers.json)
  issue=$(echo "$old_worker" | jq -r '.issue')
  attempt=$(echo "$old_worker" | jq -r '.attempt')
  worktree=$(echo "$old_worker" | jq -r '.worktree')

  # Check for handover file
  handover_file="$worktree/.orchestrator/handover-$issue.md"

  if [ ! -f "$handover_file" ]; then
    # Try alternative location
    handover_file=".orchestrator/handover-$issue.md"
  fi

  # Cleanup old worker but KEEP worktree (new worker takes over)
  cleanup_worker "$old_worker_id" true

  # Spawn replacement with same worktree and handover context
  new_worker_id="worker-$(date +%s)-$issue"

  prompt=$(construct_worker_prompt "$issue" "$new_worker_id" "$handover_file" "$((attempt + 1))" "")

  # Spawn in existing worktree
  spawn_worker_process "$issue" "$new_worker_id" "$worktree" "$prompt"

  # Update with handover reference
  jq --arg id "$new_worker_id" --arg from "$old_worker_id" \
     '(.workers[] | select(.id == $id)).handover_from = $from' \
     .orchestrator/workers.json > .orchestrator/workers.json.tmp
  mv .orchestrator/workers.json.tmp .orchestrator/workers.json

  log_activity "worker_replacement" "$new_worker_id" "$issue" "$old_worker_id"
}
```

## Parallel Dispatch

```bash
dispatch_available_slots() {
  max_workers=5
  current=$(jq '.workers | length' .orchestrator/workers.json)
  available=$((max_workers - current))

  if [ "$available" -le 0 ]; then
    echo "No worker slots available ($current/$max_workers active)"
    return
  fi

  echo "Dispatching up to $available workers..."

  for i in $(seq 1 $available); do
    next_issue=$(get_next_pending_issue)

    if [ -z "$next_issue" ]; then
      echo "No more pending issues"
      break
    fi

    spawn_worker "$next_issue"
  done
}
```

## Environment Injection

Workers inherit orchestrator's environment plus:

```bash
export WORKER_ID="$worker_id"
export WORKER_ISSUE="$issue"
export ORCHESTRATION_ID="$ORCHESTRATION_ID"
export GITHUB_OWNER="$GITHUB_OWNER"
export GITHUB_REPO="$GITHUB_REPO"
export GITHUB_PROJECT="$GITHUB_PROJECT"
```

## Checklist

When spawning a worker:

- [ ] Worktree created successfully
- [ ] Branch created/checked out
- [ ] Worker prompt constructed with all context
- [ ] Appropriate tool scoping applied
- [ ] Process spawned in background
- [ ] PID recorded
- [ ] Worker registered in workers.json
- [ ] Issue moved to in_progress queue
- [ ] Activity logged

When cleaning up:

- [ ] Worker process terminated (or already exited)
- [ ] Worktree removed (unless keeping for inspection)
- [ ] Worker removed from workers.json
- [ ] PID file removed
- [ ] Activity logged

## Integration

This skill is used by:
- `autonomous-orchestration` - Main orchestration loop

This skill uses:
- `worker-protocol` - Behavior injected into prompts
- `worker-handover` - Handover file format
