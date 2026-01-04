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
PLAN_LIMIT_PATTERNS=(
  "rate.?limit"
  "quota.?exceeded"
  "usage.?limit"
  "plan.?limit"
  "too.?many.?requests"
  "capacity.?limit"
  "request.?limit"
  "token.?limit"
  "monthly.?limit"
  "daily.?limit"
  "hour.?limit"
  "minute.?limit"
  "exceeded.?your"
  "limit.?reached"
  "try.?again.?later"
  "throttl"
  "429"
  "503"
  "overloaded"
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

  # Build combined regex pattern
  local pattern=""
  for p in "${PLAN_LIMIT_PATTERNS[@]}"; do
    [[ -n "$pattern" ]] && pattern="${pattern}|"
    pattern="${pattern}${p}"
  done

  # Search last 50 lines of transcript (most recent activity)
  if tail -50 "$transcript_path" 2>/dev/null | grep -qiE "$pattern"; then
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

      # Output block decision with switch instructions
      # The reason will be shown to Claude and guide its next action
      jq -n \
        --arg current "$current_email" \
        --arg next "$next_account" \
        '{
          "decision": "block",
          "reason": ("Plan limit reached on " + $current + ". Switching to account: " + $next + ". Please run: claude-account switch " + $next + " && echo \"Account switched. Continuing work...\" Then continue with the current task."),
          "systemMessage": ("Plan limit hit - switching from " + $current + " to " + $next)
        }'

      exit 0
    else
      # No available accounts - allow stop, enter SLEEP mode
      echo "Plan limit reached. No available accounts to switch to. All accounts exhausted or in cooldown." >&2

      # Output message for user
      jq -n \
        --arg current "$current_email" \
        '{
          "decision": "block",
          "reason": ("Plan limit reached on all accounts. Entering SLEEP mode. To resume: wait for cooldown (" + (env.CLAUDE_ACCOUNT_COOLDOWN_MINUTES // "5") + " minutes) or add more accounts with claude-account capture."),
          "systemMessage": "All accounts exhausted - entering SLEEP"
        }'

      exit 0
    fi
  fi

  # No plan limit detected - allow normal stop evaluation
  exit 0
}

main "$@"
