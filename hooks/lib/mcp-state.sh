#!/usr/bin/env bash
# MCP Memory state caching for orchestration
#
# Implements dual-write pattern:
# - Write: GitHub first (authoritative), then MCP Memory (cache)
# - Read: MCP Memory first (fast), fall back to GitHub if stale/missing
#
# This library works alongside github-state.sh to provide fast state access
# while ensuring GitHub remains the authoritative source of truth.
#
# Usage:
#   source lib/mcp-state.sh
#   source lib/github-state.sh
#
#   # Dual-write pattern
#   set_orchestration_state "running" '{"phase": "impl"}'  # GitHub
#   sync_state_to_mcp "orchestration" "$state_json"        # MCP cache
#
#   # Fast read with fallback
#   state=$(read_state_with_fallback "orchestration" "$issue_number")
#
# Note: MCP Memory operations require the mcp__memory__ tools which are
# available to Claude but not to shell scripts. This library provides
# helper functions and documentation for Claude to use during skill execution.

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/log-event.sh" ]; then
  source "$SCRIPT_DIR/log-event.sh"
fi

# ============================================================================
# MCP Memory Entity Schemas
# ============================================================================

# These document the entity types used in MCP Memory for state caching.
# Claude should use mcp__memory__create_entities and mcp__memory__add_observations
# to manage these entities.

# Entity: orchestration-state
# Type: StateCache
# Observations:
#   - "status:<status>" (running, sleeping, stopped, error)
#   - "updated:<timestamp>"
#   - "tracking_issue:<number>"
#   - "current_phase:<phase>"
#   - "state_json:<json>"

# Entity: worker-<issue_number>
# Type: WorkerCache
# Observations:
#   - "worker_id:<id>"
#   - "assigned_at:<timestamp>"
#   - "issue:<number>"
#   - "status:<status>"

# Entity: handover-<issue_number>
# Type: HandoverCache
# Observations:
#   - "prev_session:<id>"
#   - "created_at:<timestamp>"
#   - "content_hash:<hash>"

# ============================================================================
# Cache Key Generation
# ============================================================================

# Generate MCP entity name for orchestration state
# Arguments:
#   $1 - Tracking issue number (optional)
get_orchestration_entity() {
  local issue="${1:-${TRACKING_ISSUE:-global}}"
  echo "orchestration-state-$issue"
}

# Generate MCP entity name for worker state
# Arguments:
#   $1 - Issue number
get_worker_entity() {
  local issue="$1"
  echo "worker-$issue"
}

# Generate MCP entity name for handover
# Arguments:
#   $1 - Issue number
get_handover_entity() {
  local issue="$1"
  echo "handover-$issue"
}

# ============================================================================
# State Synchronization Helpers
# ============================================================================

# Format state for MCP observation
# Arguments:
#   $1 - State type (status, phase, etc.)
#   $2 - Value
format_observation() {
  local type="$1"
  local value="$2"
  echo "$type:$value"
}

# Generate MCP entity creation JSON for Claude
# Arguments:
#   $1 - Entity name
#   $2 - Entity type
#   $3 - Observations (JSON array or newline-separated)
generate_entity_json() {
  local name="$1"
  local entity_type="$2"
  local observations="$3"

  # If observations is not a JSON array, convert it
  local obs_array
  if echo "$observations" | jq -e '.' >/dev/null 2>&1; then
    obs_array="$observations"
  else
    # Convert newline-separated to JSON array
    obs_array=$(echo "$observations" | jq -R '.' | jq -s '.')
  fi

  jq -cn \
    --arg name "$name" \
    --arg type "$entity_type" \
    --argjson obs "$obs_array" \
    '{
      name: $name,
      entityType: $type,
      observations: $obs
    }'
}

# ============================================================================
# Instructions for Claude
# ============================================================================

# Print instructions for Claude on how to sync state to MCP
# Call this from skills to guide Claude's behavior
print_mcp_sync_instructions() {
  cat <<'EOF'
## MCP Memory Sync Instructions

After writing state to GitHub, sync to MCP Memory for fast reads:

### Orchestration State
```
Use mcp__memory__create_entities with:
{
  "entities": [{
    "name": "orchestration-state-<issue>",
    "entityType": "StateCache",
    "observations": [
      "status:<running|sleeping|stopped|error>",
      "updated:<ISO timestamp>",
      "tracking_issue:<number>",
      "state_json:<escaped JSON>"
    ]
  }]
}
```

### Worker Assignment
```
Use mcp__memory__create_entities with:
{
  "entities": [{
    "name": "worker-<issue>",
    "entityType": "WorkerCache",
    "observations": [
      "worker_id:<session id>",
      "assigned_at:<ISO timestamp>",
      "issue:<number>"
    ]
  }]
}
```

### Reading State (Fast Path)
```
1. Use mcp__memory__search_nodes with query "orchestration-state-<issue>"
2. If found and recent (< 5 min), use cached value
3. If not found or stale, query GitHub and update cache
```

### Cache Invalidation
```
When state changes, update MCP entity observations using:
mcp__memory__add_observations
```
EOF
}

# ============================================================================
# Shell-Accessible Cache Helpers
# ============================================================================

# Check if we're in a context where MCP is available
# Returns: 0 if MCP available hint, 1 otherwise
check_mcp_context() {
  # MCP tools are only available to Claude, not shell scripts
  # This returns 1 to indicate shell should use GitHub directly
  return 1
}

# Calculate content hash for cache validation
# Arguments:
#   $1 - Content to hash
content_hash() {
  local content="$1"
  echo "$content" | md5sum | cut -d' ' -f1
}

# Check if cached value is stale (> 5 minutes old)
# Arguments:
#   $1 - Cached timestamp (ISO format)
# Returns: 0 if stale, 1 if fresh
is_cache_stale() {
  local cached_ts="$1"
  local max_age_seconds=300  # 5 minutes

  if [ -z "$cached_ts" ]; then
    return 0  # No timestamp = stale
  fi

  local cached_epoch
  local now_epoch

  # Try to parse timestamp
  if command -v gdate &>/dev/null; then
    # macOS with coreutils
    cached_epoch=$(gdate -d "$cached_ts" +%s 2>/dev/null || echo 0)
    now_epoch=$(gdate +%s)
  else
    # Linux
    cached_epoch=$(date -d "$cached_ts" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
  fi

  local age=$((now_epoch - cached_epoch))

  if [ "$age" -gt "$max_age_seconds" ]; then
    return 0  # Stale
  fi
  return 1  # Fresh
}

# ============================================================================
# Dual-Write Pattern Implementation
# ============================================================================

# This section documents the dual-write pattern for Claude to follow.
# Shell scripts should use github-state.sh directly.

# The pattern is:
# 1. Write to GitHub first (authoritative)
# 2. If GitHub write succeeds, update MCP cache
# 3. On read: check MCP first, fall back to GitHub
# 4. On cache miss or stale: read from GitHub, update cache

# Example workflow for Claude:
#
# async function setOrchestrationState(status, data) {
#   // 1. Write to GitHub (authoritative)
#   await githubWriteState(status, data);
#
#   // 2. Update MCP cache
#   await mcp__memory__add_observations({
#     observations: [{
#       entityName: `orchestration-state-${issue}`,
#       contents: [
#         `status:${status}`,
#         `updated:${new Date().toISOString()}`,
#         `state_json:${JSON.stringify(data)}`
#       ]
#     }]
#   });
# }
#
# async function getOrchestrationState() {
#   // 1. Try MCP cache first
#   const cached = await mcp__memory__search_nodes({
#     query: `orchestration-state-${issue}`
#   });
#
#   if (cached && !isStale(cached.updated)) {
#     return parseState(cached);
#   }
#
#   // 2. Fall back to GitHub
#   const state = await githubReadState();
#
#   // 3. Update cache
#   await syncToMcp(state);
#
#   return state;
# }

# Log that this library was sourced
log_hook_event "Library" "mcp-state" "loaded" '{}' 2>/dev/null || true
