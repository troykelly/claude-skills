#!/usr/bin/env bash
# JSON event logging utility for Claude Code hooks
#
# Provides structured logging for observability and debugging.
# All events are logged to a central JSON-lines file.
#
# Usage:
#   source lib/log-event.sh
#   log_hook_event "PreToolUse" "validate-tests" "blocked" '{"reason": "tests failed"}'
#
# Helper functions:
#   json_encode "string"           - Safely encode a string for JSON
#   json_obj key1 val1 key2 val2   - Build a JSON object with proper escaping

# Determine log directory
HOOK_LOG_DIR="${CLAUDE_HOOK_LOGS:-${CLAUDE_PROJECT_DIR:-.}/.claude/logs}"

# Ensure log directory exists
mkdir -p "$HOOK_LOG_DIR" 2>/dev/null || true

# Log file path (JSON lines format)
HOOK_LOG_FILE="$HOOK_LOG_DIR/hook-events.jsonl"

# Safely encode a string for JSON inclusion
# Usage: json_encode "string with \"quotes\" and \n newlines"
# Returns: properly escaped JSON string (without surrounding quotes)
json_encode() {
  local str="${1:-}"
  # Use jq to properly escape the string, then strip the surrounding quotes
  printf '%s' "$str" | jq -Rs '.' | sed 's/^"//;s/"$//'
}

# Build a JSON object with proper string escaping
# Usage: json_obj "key1" "value1" "key2" "value2"
# Returns: {"key1": "value1", "key2": "value2"}
# Note: All values are treated as strings. For numbers/booleans, use json_obj_mixed
json_obj() {
  local result="{"
  local first=true
  local key val escaped_key escaped_val

  while [ $# -ge 2 ]; do
    key="$1"
    val="$2"
    shift 2

    if [ "$first" = "true" ]; then
      first=false
    else
      result="${result}, "
    fi

    # Use jq to properly escape both key and value
    escaped_key=$(printf '%s' "$key" | jq -Rs '.')
    escaped_val=$(printf '%s' "$val" | jq -Rs '.')
    result="${result}${escaped_key}: ${escaped_val}"
  done
  result="${result}}"
  printf '%s' "$result"
}

# Build a JSON object with mixed types (strings, numbers, booleans)
# Usage: json_obj_mixed "key1" "s:string_value" "key2" "n:42" "key3" "b:true"
# Prefixes: s: = string, n: = number, b: = boolean, r: = raw JSON
json_obj_mixed() {
  local result="{"
  local first=true
  local key typed_val escaped_key val_type val escaped_val

  while [ $# -ge 2 ]; do
    key="$1"
    typed_val="$2"
    shift 2

    if [ "$first" = "true" ]; then
      first=false
    else
      result="${result}, "
    fi

    escaped_key=$(printf '%s' "$key" | jq -Rs '.')

    val_type="${typed_val%%:*}"
    val="${typed_val#*:}"

    case "$val_type" in
      s)
        escaped_val=$(printf '%s' "$val" | jq -Rs '.')
        result="${result}${escaped_key}: ${escaped_val}"
        ;;
      n)
        # Validate it's a number, default to 0 if not
        if [[ "$val" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
          result="${result}${escaped_key}: ${val}"
        else
          result="${result}${escaped_key}: 0"
        fi
        ;;
      b)
        # Validate it's a boolean, default to false if not
        if [ "$val" = "true" ] || [ "$val" = "false" ]; then
          result="${result}${escaped_key}: ${val}"
        else
          result="${result}${escaped_key}: false"
        fi
        ;;
      r)
        # Raw JSON - validate it's valid JSON first
        if echo "$val" | jq -e . >/dev/null 2>&1; then
          result="${result}${escaped_key}: ${val}"
        else
          result="${result}${escaped_key}: null"
        fi
        ;;
      *)
        # Default to string if no prefix
        escaped_val=$(printf '%s' "$typed_val" | jq -Rs '.')
        result="${result}${escaped_key}: ${escaped_val}"
        ;;
    esac
  done
  result="${result}}"
  printf '%s' "$result"
}

# Function to log a hook event
# Arguments:
#   $1 - Hook type (SessionStart, PreToolUse, PostToolUse, Stop, etc.)
#   $2 - Hook name (script name or identifier)
#   $3 - Event type (started, completed, blocked, error, etc.)
#   $4 - Additional data (JSON object, optional)
log_hook_event() {
  local hook_type="${1:-unknown}"
  local hook_name="${2:-unknown}"
  local event_type="${3:-unknown}"
  local data
  data="${4:-"{}"}"

  # Validate data is valid JSON, default to empty object if not
  if ! echo "$data" | jq -e . >/dev/null 2>&1; then
    # Use jq to properly escape the raw data as a string
    local escaped_raw
    escaped_raw=$(printf '%s' "$data" | head -c 500 | jq -Rs '.')
    data="{\"raw\": ${escaped_raw}, \"parse_error\": true}"
  fi

  # Get session info if available
  local session_id="${CLAUDE_SESSION_ID:-}"
  if [ -z "$session_id" ] && [ -f "/tmp/claude-session-marker" ]; then
    session_id=$(cat /tmp/claude-session-marker 2>/dev/null || echo "")
  fi

  # Get git info if available
  local git_branch=""
  local git_repo=""
  if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
    git_branch=$(git branch --show-current 2>/dev/null || echo "")
    git_repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
  fi

  # Build the log entry
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local log_entry
  log_entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg hook_type "$hook_type" \
    --arg hook_name "$hook_name" \
    --arg event "$event_type" \
    --arg session "$session_id" \
    --arg branch "$git_branch" \
    --arg repo "$git_repo" \
    --argjson data "$data" \
    '{
      timestamp: $ts,
      hook_type: $hook_type,
      hook_name: $hook_name,
      event: $event,
      session_id: (if $session != "" then $session else null end),
      git: {
        branch: (if $branch != "" then $branch else null end),
        repo: (if $repo != "" then $repo else null end)
      },
      data: $data
    }')

  # Append to log file
  echo "$log_entry" >> "$HOOK_LOG_FILE" 2>/dev/null || true

  # Also output to a per-hook-type file for easier filtering
  local hook_type_lower
  hook_type_lower=$(printf '%s' "$hook_type" | tr '[:upper:]' '[:lower:]')
  local type_log_file="$HOOK_LOG_DIR/${hook_type_lower}-events.jsonl"
  echo "$log_entry" >> "$type_log_file" 2>/dev/null || true
}

# Function to query recent events (useful for debugging)
# Arguments:
#   $1 - Number of events to show (default 10)
#   $2 - Filter by hook_type (optional)
query_hook_events() {
  local limit="${1:-10}"
  local filter="${2:-}"

  if [ ! -f "$HOOK_LOG_FILE" ]; then
    echo "No hook events logged yet"
    return 0
  fi

  if [ -n "$filter" ]; then
    tail -n "$limit" "$HOOK_LOG_FILE" | jq -c "select(.hook_type == \"$filter\")"
  else
    tail -n "$limit" "$HOOK_LOG_FILE" | jq -c '.'
  fi
}

# Function to get event counts by type
hook_event_summary() {
  if [ ! -f "$HOOK_LOG_FILE" ]; then
    echo "No hook events logged yet"
    return 0
  fi

  jq -s 'group_by(.hook_type) | map({type: .[0].hook_type, count: length}) | sort_by(-.count)' "$HOOK_LOG_FILE"
}
