---
name: ci-monitor
description: Monitors CI/PR status for orchestration. Implements SLEEP/WAKE patterns via polling, hooks, and webhooks. Handles CI failures and auto-merge.
---

# CI Monitor

## Overview

Monitors CI status for open PRs and implements WAKE mechanisms to resume orchestration when CI completes.

**Core principle:** Don't burn tokens polling. SLEEP efficiently, WAKE promptly.

**Announce at start:** "I'm using ci-monitor to track CI status for open PRs."

## CI Status Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   PR Created    │────▶│   CI Running    │────▶│   CI Complete   │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                              ┌──────────────────────────┼──────────────────────────┐
                              ▼                          ▼                          ▼
                     ┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
                     │   All Passed    │       │  Some Failed    │       │   All Failed    │
                     │   → Auto-Merge  │       │   → Investigate │       │   → Re-queue    │
                     └─────────────────┘       └─────────────────┘       └─────────────────┘
```

## Checking CI Status

### GitHub CLI Commands

```bash
# List PR checks
gh pr checks [PR_NUMBER] --json name,state,conclusion

# Example output:
# [
#   {"name": "build", "state": "SUCCESS", "conclusion": "SUCCESS"},
#   {"name": "test", "state": "SUCCESS", "conclusion": "SUCCESS"},
#   {"name": "lint", "state": "FAILURE", "conclusion": "FAILURE"}
# ]

# Check if all passed
gh pr checks [PR_NUMBER] --json state --jq 'all(.[]; .state == "SUCCESS")'

# Check if any still running
gh pr checks [PR_NUMBER] --json state --jq 'any(.[]; .state == "PENDING")'

# Check if any failed
gh pr checks [PR_NUMBER] --json state --jq 'any(.[]; .state == "FAILURE")'
```

### Status Evaluation

```bash
evaluate_ci_status() {
  pr=$1

  checks=$(gh pr checks "$pr" --json name,state,conclusion 2>/dev/null)

  if [ -z "$checks" ]; then
    echo "unknown"
    return
  fi

  pending=$(echo "$checks" | jq 'any(.[]; .state == "PENDING")')
  failed=$(echo "$checks" | jq 'any(.[]; .state == "FAILURE")')
  all_passed=$(echo "$checks" | jq 'all(.[]; .state == "SUCCESS")')

  if [ "$pending" = "true" ]; then
    echo "running"
  elif [ "$failed" = "true" ]; then
    echo "failed"
  elif [ "$all_passed" = "true" ]; then
    echo "passed"
  else
    echo "unknown"
  fi
}
```

## SLEEP/WAKE Pattern

### Entering SLEEP

When orchestrator has no active work (only waiting on CI):

```bash
enter_sleep() {
  reason=$1
  waiting_prs=$2  # JSON array of PR numbers

  # Update state
  jq --arg reason "$reason" \
     --arg since "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --argjson prs "$waiting_prs" \
     '.sleep = {
       sleeping: true,
       reason: $reason,
       since: $since,
       waiting_on: $prs
     }' .orchestrator/state.json > .orchestrator/state.json.tmp
  mv .orchestrator/state.json.tmp .orchestrator/state.json

  # Start wake monitor (if not already running)
  start_wake_monitor

  # Log
  log_activity "sleep_started" "$reason"

  # Report
  echo "## Orchestration Sleeping"
  echo ""
  echo "**Reason:** $reason"
  echo "**Waiting on PRs:** $(echo "$waiting_prs" | jq -r 'join(", ")')"
  echo ""
  echo "**Wake mechanisms active:**"
  echo "- Polling: Every 5 minutes"
  echo "- Hook: SessionStart will check"
  [ -n "$WEBHOOK_PORT" ] && echo "- Webhook: Listening on port $WEBHOOK_PORT"
  echo ""
  echo "**Manual wake:** \`claude --resume $RESUME_SESSION\`"
}
```

### WAKE Trigger

```bash
trigger_wake() {
  reason=$1

  # Update state
  jq '.sleep.sleeping = false' .orchestrator/state.json > .orchestrator/state.json.tmp
  mv .orchestrator/state.json.tmp .orchestrator/state.json

  log_activity "wake_triggered" "$reason"

  # Resume orchestration
  echo "Waking orchestration: $reason"
}
```

## Wake Mechanism 1: Polling Script

Simple background script that polls CI status:

### Script: `.orchestrator/wake-poll.sh`

```bash
#!/usr/bin/env bash
# Wake monitor via polling
# Run with: nohup ./.orchestrator/wake-poll.sh &

set -euo pipefail

STATE_FILE=".orchestrator/state.json"
POLL_INTERVAL=${WAKE_POLL_INTERVAL:-300}  # 5 minutes default
LOG_FILE=".orchestrator/logs/wake-poll.log"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG_FILE"
}

check_and_wake() {
  # Is orchestration sleeping?
  sleeping=$(jq -r '.sleep.sleeping' "$STATE_FILE" 2>/dev/null || echo "false")

  if [ "$sleeping" != "true" ]; then
    log "Not sleeping, nothing to do"
    return
  fi

  # Get PRs we're waiting on
  waiting_prs=$(jq -r '.sleep.waiting_on[]' "$STATE_FILE" 2>/dev/null)

  if [ -z "$waiting_prs" ]; then
    log "No PRs to wait on"
    return
  fi

  # Check each PR
  all_complete=true
  for pr in $waiting_prs; do
    status=$(gh pr checks "$pr" --json state --jq 'all(.[]; .state != "PENDING")' 2>/dev/null || echo "false")

    if [ "$status" != "true" ]; then
      log "PR #$pr still running"
      all_complete=false
      break
    fi
  done

  if [ "$all_complete" = "true" ]; then
    log "All PRs complete, waking orchestration"

    # Get resume session
    resume_session=$(jq -r '.resume_session' "$STATE_FILE")

    # Wake by resuming session
    claude --resume "$resume_session" -p "CI checks complete. Resume orchestration loop." \
      --max-turns 1000 \
      --permission-mode acceptEdits &

    log "Orchestration resumed"
    exit 0  # Our job is done
  fi
}

log "Wake monitor started (poll interval: ${POLL_INTERVAL}s)"

while true; do
  check_and_wake
  sleep "$POLL_INTERVAL"
done
```

### Starting/Stopping Poller

```bash
start_wake_monitor() {
  if [ -f ".orchestrator/pids/wake-poll.pid" ]; then
    pid=$(cat .orchestrator/pids/wake-poll.pid)
    if kill -0 "$pid" 2>/dev/null; then
      echo "Wake monitor already running (PID: $pid)"
      return
    fi
  fi

  nohup ./.orchestrator/wake-poll.sh > /dev/null 2>&1 &
  echo $! > .orchestrator/pids/wake-poll.pid
  echo "Wake monitor started (PID: $!)"
}

stop_wake_monitor() {
  if [ -f ".orchestrator/pids/wake-poll.pid" ]; then
    pid=$(cat .orchestrator/pids/wake-poll.pid)
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "Wake monitor stopped"
    fi
    rm -f .orchestrator/pids/wake-poll.pid
  fi
}
```

## Wake Mechanism 2: SessionStart Hook

Hook that checks SLEEP status when starting a new session:

### Hook: `hooks/check-orchestration-sleep.sh`

```bash
#!/usr/bin/env bash
# SessionStart hook to check if orchestration should wake

STATE_FILE=".orchestrator/state.json"

# Skip if no orchestration state
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

sleeping=$(jq -r '.sleep.sleeping' "$STATE_FILE" 2>/dev/null || echo "false")

if [ "$sleeping" = "true" ]; then
  reason=$(jq -r '.sleep.reason' "$STATE_FILE")
  since=$(jq -r '.sleep.since' "$STATE_FILE")
  waiting=$(jq -r '.sleep.waiting_on | join(", ")' "$STATE_FILE")

  echo "## Orchestration Was Sleeping"
  echo ""
  echo "**Reason:** $reason"
  echo "**Since:** $since"
  echo "**Waiting on PRs:** $waiting"
  echo ""
  echo "Checking CI status..."

  # Check if wake conditions met
  all_complete=true
  for pr in $(jq -r '.sleep.waiting_on[]' "$STATE_FILE"); do
    if ! gh pr checks "$pr" --json state --jq 'all(.[]; .state != "PENDING")' | grep -q "true"; then
      all_complete=false
      break
    fi
  done

  if [ "$all_complete" = "true" ]; then
    echo ""
    echo "✅ CI complete! Orchestration will resume."
  else
    echo ""
    echo "⏳ CI still running. Orchestration remains asleep."
    echo ""
    echo "To check manually: \`gh pr checks [PR]\`"
    echo "To force wake: \`claude --resume $RESUME_SESSION -p 'Resume orchestration'\`"
  fi
fi

exit 0
```

### Hook Configuration

Add to `hooks/hooks.json`:

```json
{
  "hooks": [
    {
      "event": "SessionStart",
      "type": "command",
      "command": ".orchestrator/hooks/check-orchestration-sleep.sh"
    }
  ]
}
```

## Wake Mechanism 3: Webhook Server

⚠️ **PORT SAFETY WARNING**

Webhooks require opening a local port. This has security implications:
- Only bind to localhost unless absolutely necessary
- Use high ports (>1024) to avoid privilege issues
- Don't expose to public internet without authentication
- Check port availability before binding

### Script: `.orchestrator/wake-webhook.sh`

```bash
#!/usr/bin/env bash
# Webhook receiver for CI completion events
# CAUTION: Opens a local port

set -euo pipefail

# Configuration
PORT=${WEBHOOK_PORT:-9876}
BIND_ADDR="${WEBHOOK_BIND:-[::1]}"  # IPv6 localhost by default
STATE_FILE=".orchestrator/state.json"
LOG_FILE=".orchestrator/logs/wake-webhook.log"
SECRET=${WEBHOOK_SECRET:-""}

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG_FILE"
}

# Check port availability
check_port() {
  if nc -z "$BIND_ADDR" "$PORT" 2>/dev/null; then
    log "ERROR: Port $PORT already in use"
    echo "ERROR: Port $PORT is already in use"
    exit 1
  fi
}

# Validate webhook signature (if secret configured)
validate_signature() {
  payload=$1
  signature=$2

  if [ -z "$SECRET" ]; then
    return 0  # No secret, skip validation
  fi

  expected=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')

  if [ "sha256=$expected" != "$signature" ]; then
    log "Invalid webhook signature"
    return 1
  fi
  return 0
}

# Handle incoming webhook
handle_webhook() {
  read -r request_line
  method=$(echo "$request_line" | awk '{print $1}')
  path=$(echo "$request_line" | awk '{print $2}')

  # Read headers
  declare -A headers
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    [ -z "$line" ] && break
    key=$(echo "$line" | cut -d: -f1)
    value=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
    headers["$key"]=$value
  done

  # Read body
  content_length=${headers["Content-Length"]:-0}
  body=""
  if [ "$content_length" -gt 0 ]; then
    body=$(head -c "$content_length")
  fi

  log "Received: $method $path"

  # Health check
  if [ "$path" = "/health" ]; then
    echo "HTTP/1.1 200 OK"
    echo "Content-Type: text/plain"
    echo ""
    echo "OK"
    return
  fi

  # Webhook endpoint
  if [ "$path" = "/webhook" ] && [ "$method" = "POST" ]; then
    # Validate signature
    signature=${headers["X-Hub-Signature-256"]:-""}
    if ! validate_signature "$body" "$signature"; then
      echo "HTTP/1.1 403 Forbidden"
      echo ""
      return
    fi

    # Parse event
    event=${headers["X-GitHub-Event"]:-"unknown"}
    log "GitHub event: $event"

    # Handle check_run or workflow_run completion
    if [ "$event" = "check_run" ] || [ "$event" = "workflow_run" ]; then
      action=$(echo "$body" | jq -r '.action')
      conclusion=$(echo "$body" | jq -r '.check_run.conclusion // .workflow_run.conclusion')

      if [ "$action" = "completed" ]; then
        log "CI completed with: $conclusion"

        # Check if this affects our PRs
        check_wake_conditions

        echo "HTTP/1.1 200 OK"
        echo ""
        echo "Processed"
        return
      fi
    fi

    echo "HTTP/1.1 200 OK"
    echo ""
    echo "Ignored"
    return
  fi

  echo "HTTP/1.1 404 Not Found"
  echo ""
}

check_wake_conditions() {
  sleeping=$(jq -r '.sleep.sleeping' "$STATE_FILE" 2>/dev/null || echo "false")

  if [ "$sleeping" != "true" ]; then
    return
  fi

  # Check all PRs
  all_complete=true
  for pr in $(jq -r '.sleep.waiting_on[]' "$STATE_FILE" 2>/dev/null); do
    if ! gh pr checks "$pr" --json state --jq 'all(.[]; .state != "PENDING")' 2>/dev/null | grep -q "true"; then
      all_complete=false
      break
    fi
  done

  if [ "$all_complete" = "true" ]; then
    log "All PRs complete, triggering wake"
    resume_session=$(jq -r '.resume_session' "$STATE_FILE")

    # Wake orchestration
    claude --resume "$resume_session" -p "CI complete (webhook trigger). Resume orchestration." \
      --max-turns 1000 \
      --permission-mode acceptEdits &

    log "Orchestration resumed"
  fi
}

# Main
check_port
log "Webhook server starting on $BIND_ADDR:$PORT"
echo "Webhook server listening on $BIND_ADDR:$PORT"
echo "Configure GitHub webhook URL: http://your-host:$PORT/webhook"

# Simple HTTP server using netcat
while true; do
  nc -l "$BIND_ADDR" "$PORT" -c 'bash -c "handle_webhook"' 2>/dev/null || true
done
```

### Port Safety Checklist

Before starting webhook server:

- [ ] Port is available (`nc -z [::1] $PORT` fails)
- [ ] Binding to localhost only (not `0.0.0.0`)
- [ ] Using IPv6 localhost `[::1]` (IPv6-first)
- [ ] Port is high (>1024)
- [ ] Webhook secret configured (if exposed)
- [ ] Firewall rules reviewed

### GitHub Webhook Configuration

If exposing webhook (e.g., via ngrok or public server):

1. Go to Repository → Settings → Webhooks
2. Add webhook:
   - Payload URL: `http://your-host:9876/webhook`
   - Content type: `application/json`
   - Secret: `[your secret]`
   - Events: Select "Check runs" and "Workflow runs"

## CI Failure Handling

### Failure Classification

```bash
classify_ci_failure() {
  pr=$1

  failed_checks=$(gh pr checks "$pr" --json name,conclusion \
    --jq '.[] | select(.conclusion == "FAILURE") | .name')

  # Classify by check name
  for check in $failed_checks; do
    case "$check" in
      *test*|*spec*)
        echo "test_failure"
        return
        ;;
      *lint*|*format*)
        echo "lint_failure"
        return
        ;;
      *build*|*compile*)
        echo "build_failure"
        return
        ;;
      *security*|*vulnerability*)
        echo "security_failure"
        return
        ;;
      *)
        echo "unknown_failure"
        return
        ;;
    esac
  done
}
```

### Handling Failures

```bash
handle_ci_failure() {
  pr=$1
  issue=$(get_pr_issue "$pr")
  failure_type=$(classify_ci_failure "$pr")

  case "$failure_type" in
    "test_failure")
      # Re-queue for worker to fix
      gh issue comment "$issue" --body "## CI Failed: Tests

PR #$pr has failing tests. Re-queuing for fix.

$(gh pr checks "$pr" --json name,conclusion --jq '.[] | select(.conclusion == \"FAILURE\") | \"- \" + .name')"
      requeue_issue "$issue"
      ;;

    "lint_failure")
      # Often auto-fixable
      gh issue comment "$issue" --body "## CI Failed: Linting

PR #$pr has lint failures. Re-queuing for auto-fix attempt."
      requeue_issue "$issue" "lint_fix"
      ;;

    "build_failure")
      # Needs investigation
      gh issue comment "$issue" --body "## CI Failed: Build

PR #$pr failed to build. Re-queuing for investigation."
      requeue_issue "$issue"
      ;;

    "security_failure")
      # Flag for human review
      gh issue comment "$issue" --body "## ⚠️ CI Failed: Security

PR #$pr has security issues. **Requires human review.**"
      mark_issue_blocked "$issue" "Security review required"
      ;;
  esac
}
```

## Auto-Merge

When enabled and CI passes:

```bash
auto_merge_pr() {
  pr=$1

  # Verify all checks passed
  if ! gh pr checks "$pr" --json state --jq 'all(.[]; .state == "SUCCESS")' | grep -q "true"; then
    echo "Cannot auto-merge: checks not all passed"
    return 1
  fi

  # Verify PR is mergeable
  mergeable=$(gh pr view "$pr" --json mergeable --jq '.mergeable')
  if [ "$mergeable" != "MERGEABLE" ]; then
    echo "Cannot auto-merge: PR not mergeable ($mergeable)"
    return 1
  fi

  # Merge
  gh pr merge "$pr" --squash --auto

  log_activity "pr_merged" "$pr"

  # Update issue
  issue=$(get_pr_issue "$pr")
  gh issue comment "$issue" --body "## ✅ Auto-Merged

PR #$pr merged successfully.

🤖 *Orchestration: $ORCHESTRATION_ID*"

  mark_issue_complete "$issue"
}
```

### Rollback on Post-Merge Failure

```bash
rollback_merge() {
  pr=$1
  reason=$2

  # Get merge commit
  merge_commit=$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid')

  if [ -z "$merge_commit" ]; then
    echo "Cannot rollback: no merge commit found"
    return 1
  fi

  # Revert
  git fetch origin main
  git checkout main
  git pull origin main
  git revert "$merge_commit" --no-edit -m 1
  git push origin main

  log_activity "pr_reverted" "$pr" "$merge_commit"

  # Re-queue issue
  issue=$(get_pr_issue "$pr")
  gh issue comment "$issue" --body "## ⚠️ Merge Reverted

PR #$pr was reverted due to post-merge issues.

**Reason:** $reason
**Reverted commit:** $merge_commit

Issue re-queued for another attempt.

🤖 *Orchestration: $ORCHESTRATION_ID*"

  requeue_issue "$issue"
}
```

## Monitoring Dashboard

### Status Command

```bash
show_ci_status() {
  echo "## CI Status"
  echo ""

  for pr in $(get_open_prs); do
    issue=$(get_pr_issue "$pr")
    status=$(evaluate_ci_status "$pr")
    checks=$(gh pr checks "$pr" --json name,state,conclusion)
    passed=$(echo "$checks" | jq '[.[] | select(.state == "SUCCESS")] | length')
    total=$(echo "$checks" | jq 'length')

    case "$status" in
      "passed") icon="✅" ;;
      "failed") icon="❌" ;;
      "running") icon="🔄" ;;
      *) icon="❓" ;;
    esac

    echo "| PR #$pr | Issue #$issue | $icon $status | $passed/$total |"
  done
}
```

## Checklist

Setting up CI monitoring:

- [ ] GitHub CLI authenticated
- [ ] Polling script created (if using polling)
- [ ] Hook installed (if using hooks)
- [ ] Webhook server configured (if using webhooks)
- [ ] Port verified available and safe (if using webhooks)
- [ ] Auto-merge policy decided
- [ ] Failure handlers configured

During operation:

- [ ] CI status checked for each PR
- [ ] Failures classified and handled
- [ ] SLEEP entered when appropriate
- [ ] WAKE triggered when CI completes
- [ ] Auto-merge executed (if enabled)
- [ ] Rollback available if needed

## Integration

This skill is used by:
- `autonomous-orchestration` - Main orchestration loop

This skill monitors:
- GitHub Actions
- Any CI configured on repository

This skill triggers:
- `worker-dispatch` - When re-queuing failed issues
- `research-after-failure` - When CI failures need investigation
