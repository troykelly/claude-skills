#!/usr/bin/env bash
#
# plan-limit-account-switch.sh - Stop hook for detecting plan limits and switching accounts
#
# This hook intercepts Claude's exit attempts and checks if the session ended
# due to plan/rate limit exhaustion. If so, it attempts to switch to another
# available Claude Pro account and continue the work.
#
# Part of the Ralph Wiggum-inspired autonomous operation pattern.
#
# Exit codes:
#   0 - Allow stop (no plan limit detected, or no accounts available)
#   0 with JSON {"decision": "block"} - Block stop and continue with new account
#

set -euo pipefail

# Source shared libraries if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/lib/log-event.sh" ]] && source "${SCRIPT_DIR}/lib/log-event.sh"

# Claude Code config directory (respects CLAUDE_CONFIG_DIR environment variable)
# If CLAUDE_CONFIG_DIR is set: config at $CLAUDE_CONFIG_DIR/.claude.json
# Otherwise: config at ~/.claude.json
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
  CLAUDE_CONFIG="${CLAUDE_CONFIG_DIR}/.claude.json"
  EXHAUSTION_FILE="${CLAUDE_CONFIG_DIR}/.account-exhaustion.json"
else
  CLAUDE_CONFIG="${HOME}/.claude.json"
  EXHAUSTION_FILE="${HOME}/.claude/.account-exhaustion.json"
fi

# Configuration
COOLDOWN_MINUTES="${CLAUDE_ACCOUNT_COOLDOWN_MINUTES:-5}"
FLAP_THRESHOLD="${CLAUDE_ACCOUNT_FLAP_THRESHOLD:-3}"
FLAP_WINDOW_SECONDS="${CLAUDE_ACCOUNT_FLAP_WINDOW:-60}"

# Plan limit detection patterns (case-insensitive)
# These patterns are designed to be SPECIFIC to Claude API rate limiting
# and avoid false positives from normal conversation content.
#
# IMPORTANT: Patterns must NOT match our own hook output to prevent feedback loops!
# Our output contains "Plan limit reached" which would match "limit.?reached"
#
# We look for specific Claude/Anthropic API error signatures:
PLAN_LIMIT_PATTERNS=(
  # Specific Claude/Anthropic API error messages
  "claude.*rate.?limit"
  "anthropic.*rate.?limit"
  "api.*rate.?limit"
  "claude.*quota"
  "anthropic.*quota"
  "claude.*usage.?limit"
  "pro.?plan.*limit"
  "subscription.*limit"
  "messages?.?limit.*exceeded"
  "exceeded.*messages?.?limit"
  "you.?have.?reached.*limit"
  "usage.?cap"
  # HTTP errors with API context (not just bare numbers)
  "api.*429"
  "429.*rate"
  "error.*429"
  "api.*503"
  "503.*overload"
  "claude.*overload"
  "anthropic.*overload"
  # Specific throttling contexts
  "api.*throttl"
  "request.*throttl"
  "claude.*throttl"
)

# Patterns that indicate our OWN output (to exclude from matching)
SELF_OUTPUT_MARKERS=(
  "Plan limit reached on"
  "Switching to account:"
  "claude-account switch"
  "All accounts exhausted"
  "Entering SLEEP mode"
  "entering cooldown"
)

# Initialize exhaustion tracking file
init_exhaustion_file() {
  if [[ ! -f "$EXHAUSTION_FILE" ]]; then
    mkdir -p "$(dirname "$EXHAUSTION_FILE")"
    cat > "$EXHAUSTION_FILE" << EOF
{
  "exhausted": {},
  "switches": [],
  "cooldown_minutes": $COOLDOWN_MINUTES
}
EOF
    chmod 600 "$EXHAUSTION_FILE"
  fi
}

# Check if transcript contains plan limit indicators
detect_plan_limit() {
  local transcript_path="$1"

  if [[ ! -f "$transcript_path" ]]; then
    return 1
  fi

  # Build combined regex pattern for detection
  local pattern=""
  for p in "${PLAN_LIMIT_PATTERNS[@]}"; do
    [[ -n "$pattern" ]] && pattern="${pattern}|"
    pattern="${pattern}${p}"
  done

  # Build exclusion pattern for our own output (to prevent feedback loops)
  local exclude_pattern=""
  for p in "${SELF_OUTPUT_MARKERS[@]}"; do
    [[ -n "$exclude_pattern" ]] && exclude_pattern="${exclude_pattern}|"
    exclude_pattern="${exclude_pattern}${p}"
  done

  # Search last 50 lines of transcript, excluding our own output
  # 1. Get last 50 lines
  # 2. Filter out lines containing our self-output markers
  # 3. Check remaining lines for plan limit patterns
  local filtered_content
  filtered_content=$(tail -50 "$transcript_path" 2>/dev/null | grep -viE "$exclude_pattern" || true)

  if [[ -z "$filtered_content" ]]; then
    return 1
  fi

  if echo "$filtered_content" | grep -qiE "$pattern"; then
    return 0
  fi

  return 1
}

# Mark current account as exhausted
mark_exhausted() {
  local email="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  init_exhaustion_file

  local tmp_file
  tmp_file=$(mktemp)
  jq --arg email "$email" --arg ts "$timestamp" \
    '.exhausted[$email] = $ts' "$EXHAUSTION_FILE" > "$tmp_file"
  mv "$tmp_file" "$EXHAUSTION_FILE"
}

# Record an account switch (for flap detection)
record_switch() {
  local from_email="$1"
  local to_email="$2"
  local timestamp
  timestamp=$(date +%s)

  init_exhaustion_file

  local tmp_file
  tmp_file=$(mktemp)
  jq --arg from "$from_email" --arg to "$to_email" --argjson ts "$timestamp" \
    '.switches += [{"from": $from, "to": $to, "timestamp": $ts}] | .switches = (.switches | .[-20:])' \
    "$EXHAUSTION_FILE" > "$tmp_file"
  mv "$tmp_file" "$EXHAUSTION_FILE"
}

# Check if we're flapping (too many switches in short window)
is_flapping() {
  init_exhaustion_file

  local now threshold_time count
  now=$(date +%s)
  threshold_time=$((now - FLAP_WINDOW_SECONDS))

  count=$(jq --argjson threshold "$threshold_time" \
    '[.switches[] | select(.timestamp > $threshold)] | length' "$EXHAUSTION_FILE")

  [[ "$count" -ge "$FLAP_THRESHOLD" ]]
}

# Check if an account has cooled down
is_cooled_down() {
  local email="$1"

  init_exhaustion_file

  local exhausted_at now cooldown_seconds
  exhausted_at=$(jq -r --arg email "$email" '.exhausted[$email] // empty' "$EXHAUSTION_FILE")

  if [[ -z "$exhausted_at" ]]; then
    return 0  # Not exhausted, so "cooled down"
  fi

  # Convert ISO timestamp to epoch
  local exhausted_epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    exhausted_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$exhausted_at" +%s 2>/dev/null || echo 0)
  else
    exhausted_epoch=$(date -d "$exhausted_at" +%s 2>/dev/null || echo 0)
  fi

  now=$(date +%s)
  cooldown_seconds=$((COOLDOWN_MINUTES * 60))

  [[ $((now - exhausted_epoch)) -ge $cooldown_seconds ]]
}

# Get next available account (not exhausted or cooled down)
get_next_available() {
  local current_email="$1"

  # Get list of all accounts from environment
  local accounts_list=""
  local var value
  while IFS='=' read -r var value; do
    if [[ "$var" =~ ^CLAUDE_ACCOUNT_.*_EMAILADDRESS$ ]]; then
      value="${value//\"/}"
      if [[ -n "$value" ]]; then
        [[ -n "$accounts_list" ]] && accounts_list="${accounts_list},"
        accounts_list="${accounts_list}${value}"
      fi
    fi
  done < <(env)

  if [[ -z "$accounts_list" ]]; then
    return 1
  fi

  # Parse into array
  local emails=()
  IFS=',' read -ra emails <<< "$accounts_list"

  # Find next available account (round-robin from current)
  local found_current=false
  local candidate=""

  # First pass: find accounts after current
  for email in "${emails[@]}"; do
    if [[ "$found_current" == "true" ]]; then
      if [[ "$email" != "$current_email" ]] && is_cooled_down "$email"; then
        candidate="$email"
        break
      fi
    fi
    if [[ "$email" == "$current_email" ]]; then
      found_current=true
    fi
  done

  # Second pass: wrap around to beginning
  if [[ -z "$candidate" ]]; then
    for email in "${emails[@]}"; do
      if [[ "$email" == "$current_email" ]]; then
        break
      fi
      if is_cooled_down "$email"; then
        candidate="$email"
        break
      fi
    done
  fi

  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi

  return 1
}

# Get current account email from Claude config
get_current_email() {
  if [[ -f "$CLAUDE_CONFIG" ]]; then
    jq -r '.oauthAccount.emailAddress // empty' "$CLAUDE_CONFIG" 2>/dev/null
  fi
}

# Main hook logic
main() {
  # Read hook input from stdin
  local hook_input
  hook_input=$(cat)

  # Parse input
  local transcript_path stop_hook_active
  transcript_path=$(echo "$hook_input" | jq -r '.transcript_path // empty')
  stop_hook_active=$(echo "$hook_input" | jq -r '.stop_hook_active // false')

  # Prevent infinite loops - if stop_hook_active is true, we already blocked once
  if [[ "$stop_hook_active" == "true" ]]; then
    # Check if we're flapping
    if is_flapping; then
      echo "All accounts appear exhausted. Entering cooldown." >&2
      exit 0
    fi
  fi

  # Check for plan limit indicators in transcript
  if [[ -n "$transcript_path" ]] && detect_plan_limit "$transcript_path"; then
    local current_email next_account
    current_email=$(get_current_email)

    if [[ -z "$current_email" ]]; then
      # No current account info, can't switch
      exit 0
    fi

    # Mark current account as exhausted
    mark_exhausted "$current_email"

    # Try to get next available account
    if next_account=$(get_next_available "$current_email"); then
      # Record the switch for flap detection
      record_switch "$current_email" "$next_account"

      # Check for flapping before proceeding
      if is_flapping; then
        echo "Account switch flapping detected. All accounts may be exhausted. Entering cooldown." >&2
        exit 0
      fi

      # Perform the actual account switch NOW
      # Claude CLI must exit and restart to use new credentials (they're loaded at startup)
      local claude_account_cmd=""
      if command -v claude-account &>/dev/null; then
        claude_account_cmd="claude-account"
      elif [[ -x "/usr/local/bin/claude-account" ]]; then
        claude_account_cmd="/usr/local/bin/claude-account"
      fi

      if [[ -n "$claude_account_cmd" ]]; then
        # Switch account credentials - this updates ~/.claude.json
        if "$claude_account_cmd" switch "$next_account" &>/dev/null; then
          echo "Plan limit on $current_email. Switched credentials to $next_account." >&2
          echo "Claude must restart to use new credentials. Use --resume to continue." >&2
        else
          echo "Failed to switch to $next_account. Manual intervention required." >&2
        fi
      else
        echo "claude-account not found. Manual switch required: claude-account switch $next_account" >&2
      fi

      # Write switch state for claude-autonomous to detect
      local switch_file="${HOME}/.claude/.pending-account-switch"
      mkdir -p "$(dirname "$switch_file")"
      jq -n \
        --arg from "$current_email" \
        --arg to "$next_account" \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{from: $from, to: $to, timestamp: $ts, reason: "plan_limit"}' > "$switch_file"

      # Force Claude to exit by sending SIGTERM
      # Claude doesn't auto-exit on rate limits - it just stops responding
      # We need to kill it so claude-autonomous can restart with new credentials
      #
      # Find the Claude process - could be our parent or grandparent depending on shell nesting
      local claude_pid=""

      # Method 1: Walk up the process tree from our PPID
      local check_pid=$PPID
      while [[ -n "$check_pid" && "$check_pid" != "1" ]]; do
        local proc_name
        proc_name=$(ps -p "$check_pid" -o comm= 2>/dev/null || true)
        if [[ "$proc_name" == "claude" ]]; then
          claude_pid="$check_pid"
          break
        fi
        # Get parent of this process
        check_pid=$(ps -p "$check_pid" -o ppid= 2>/dev/null | tr -d ' ' || true)
      done

      # Method 2: Fallback to pgrep if we didn't find it
      if [[ -z "$claude_pid" ]]; then
        claude_pid=$(pgrep -x "claude" 2>/dev/null | head -1 || true)
      fi

      if [[ -n "$claude_pid" ]]; then
        echo "Sending SIGTERM to Claude (PID $claude_pid) to force restart..." >&2
        kill -TERM "$claude_pid" 2>/dev/null || true
        # Give it a moment to clean up
        sleep 1
        # If still running, send SIGKILL
        if kill -0 "$claude_pid" 2>/dev/null; then
          echo "Claude didn't exit, sending SIGKILL..." >&2
          kill -KILL "$claude_pid" 2>/dev/null || true
        fi
      else
        echo "Could not find Claude process to terminate. Manual restart required." >&2
      fi

      exit 0
    else
      # No available accounts - allow stop, enter SLEEP mode
      echo "Plan limit reached. No available accounts to switch to. All accounts exhausted or in cooldown." >&2

      # Write sleep state for claude-autonomous to detect
      local sleep_file="${HOME}/.claude/.account-sleep-mode"
      mkdir -p "$(dirname "$sleep_file")"
      jq -n \
        --arg account "$current_email" \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson cooldown "$COOLDOWN_MINUTES" \
        '{exhausted_account: $account, timestamp: $ts, cooldown_minutes: $cooldown, reason: "all_accounts_exhausted"}' > "$sleep_file"

      # Force Claude to exit so claude-autonomous can handle cooldown
      local claude_pid=""
      local check_pid=$PPID
      while [[ -n "$check_pid" && "$check_pid" != "1" ]]; do
        local proc_name
        proc_name=$(ps -p "$check_pid" -o comm= 2>/dev/null || true)
        if [[ "$proc_name" == "claude" ]]; then
          claude_pid="$check_pid"
          break
        fi
        check_pid=$(ps -p "$check_pid" -o ppid= 2>/dev/null | tr -d ' ' || true)
      done

      if [[ -z "$claude_pid" ]]; then
        claude_pid=$(pgrep -x "claude" 2>/dev/null | head -1 || true)
      fi

      if [[ -n "$claude_pid" ]]; then
        echo "All accounts exhausted. Terminating Claude for cooldown..." >&2
        kill -TERM "$claude_pid" 2>/dev/null || true
        sleep 1
        if kill -0 "$claude_pid" 2>/dev/null; then
          kill -KILL "$claude_pid" 2>/dev/null || true
        fi
      fi

      exit 0
    fi
  fi

  # No plan limit detected - allow normal stop evaluation
  exit 0
}

main "$@"
