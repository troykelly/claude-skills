#!/usr/bin/env bash
# Artifact validation library for Claude Code hooks
#
# Provides validation functions for generated artifacts:
# - JSON files (jq validation)
# - YAML files (yq validation)
# - Markdown files (frontmatter validation)
# - Shell scripts (bash -n syntax check)
#
# Usage:
#   source lib/validate-artifacts.sh
#   validate_json "file.json" || exit 1
#   validate_yaml "file.yaml" || exit 1
#   validate_markdown "SKILL.md" || exit 1
#   validate_shell "script.sh" || exit 1

set -euo pipefail

# Source logging if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/log-event.sh" ]; then
  source "$SCRIPT_DIR/log-event.sh"
fi

# Colors for output
readonly V_RED='\033[0;31m'
readonly V_GREEN='\033[0;32m'
readonly V_YELLOW='\033[1;33m'
readonly V_NC='\033[0m'

# ============================================================================
# JSON Validation
# ============================================================================

# Validate JSON file syntax
# Arguments:
#   $1 - File path
# Returns: 0 on success, 1 on failure
# Outputs: Error message on failure
validate_json() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo -e "${V_RED}ERROR:${V_NC} File not found: $file" >&2
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    echo -e "${V_YELLOW}WARNING:${V_NC} jq not installed, skipping JSON validation" >&2
    return 0
  fi

  local error_output
  if ! error_output=$(jq '.' "$file" 2>&1 >/dev/null); then
    echo -e "${V_RED}JSON VALIDATION FAILED:${V_NC} $file" >&2
    echo "$error_output" >&2
    log_hook_event "Validation" "validate-artifacts" "failed" \
      "$(json_obj "file" "$file" "type" "json" "error" "$error_output")" 2>/dev/null || true
    return 1
  fi

  echo -e "${V_GREEN}JSON valid:${V_NC} $file" >&2
  return 0
}

# Validate JSON string (not file)
# Arguments:
#   $1 - JSON string
# Returns: 0 on valid, 1 on invalid
validate_json_string() {
  local json_str="$1"

  if ! echo "$json_str" | jq -e '.' >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# ============================================================================
# YAML Validation
# ============================================================================

# Validate YAML file syntax
# Arguments:
#   $1 - File path
# Returns: 0 on success, 1 on failure
validate_yaml() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo -e "${V_RED}ERROR:${V_NC} File not found: $file" >&2
    return 1
  fi

  # Try yq first (preferred)
  if command -v yq &>/dev/null; then
    local error_output
    if ! error_output=$(yq '.' "$file" 2>&1 >/dev/null); then
      echo -e "${V_RED}YAML VALIDATION FAILED:${V_NC} $file" >&2
      echo "$error_output" >&2
      log_hook_event "Validation" "validate-artifacts" "failed" \
        "$(json_obj "file" "$file" "type" "yaml" "error" "$error_output")" 2>/dev/null || true
      return 1
    fi
    echo -e "${V_GREEN}YAML valid:${V_NC} $file" >&2
    return 0
  fi

  # Fallback: try python yaml module
  if command -v python3 &>/dev/null; then
    local error_output
    if ! error_output=$(python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1); then
      echo -e "${V_RED}YAML VALIDATION FAILED:${V_NC} $file" >&2
      echo "$error_output" >&2
      log_hook_event "Validation" "validate-artifacts" "failed" \
        "$(json_obj "file" "$file" "type" "yaml" "error" "$error_output")" 2>/dev/null || true
      return 1
    fi
    echo -e "${V_GREEN}YAML valid:${V_NC} $file" >&2
    return 0
  fi

  echo -e "${V_YELLOW}WARNING:${V_NC} No YAML validator found (yq or python3), skipping" >&2
  return 0
}

# ============================================================================
# Markdown Validation
# ============================================================================

# Validate markdown file with YAML frontmatter
# Arguments:
#   $1 - File path
#   $2 - Required frontmatter fields (space-separated, optional)
# Returns: 0 on success, 1 on failure
validate_markdown() {
  local file="$1"
  local required_fields="${2:-}"

  if [ ! -f "$file" ]; then
    echo -e "${V_RED}ERROR:${V_NC} File not found: $file" >&2
    return 1
  fi

  # Check if file starts with frontmatter
  local first_line
  first_line=$(head -1 "$file")

  if [ "$first_line" != "---" ]; then
    # No frontmatter - might be okay for some markdown files
    echo -e "${V_YELLOW}NOTE:${V_NC} No frontmatter in: $file" >&2
    return 0
  fi

  # Extract frontmatter
  local frontmatter
  frontmatter=$(awk '/^---$/{if(++n==2)exit}n' "$file" | tail -n +2)

  if [ -z "$frontmatter" ]; then
    echo -e "${V_RED}MARKDOWN VALIDATION FAILED:${V_NC} Empty frontmatter in $file" >&2
    return 1
  fi

  # Validate frontmatter as YAML
  if command -v yq &>/dev/null; then
    if ! echo "$frontmatter" | yq '.' >/dev/null 2>&1; then
      echo -e "${V_RED}MARKDOWN VALIDATION FAILED:${V_NC} Invalid YAML frontmatter in $file" >&2
      log_hook_event "Validation" "validate-artifacts" "failed" \
        "$(json_obj "file" "$file" "type" "markdown" "error" "invalid frontmatter yaml")" 2>/dev/null || true
      return 1
    fi

    # Check required fields if specified
    if [ -n "$required_fields" ]; then
      for field in $required_fields; do
        local value
        value=$(echo "$frontmatter" | yq ".$field // \"\"" 2>/dev/null)
        if [ -z "$value" ] || [ "$value" = "null" ]; then
          echo -e "${V_RED}MARKDOWN VALIDATION FAILED:${V_NC} Missing required field '$field' in $file" >&2
          return 1
        fi
      done
    fi
  elif command -v python3 &>/dev/null; then
    if ! echo "$frontmatter" | python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" 2>/dev/null; then
      echo -e "${V_RED}MARKDOWN VALIDATION FAILED:${V_NC} Invalid YAML frontmatter in $file" >&2
      return 1
    fi
  fi

  echo -e "${V_GREEN}Markdown valid:${V_NC} $file" >&2
  return 0
}

# Validate skill markdown file (stricter requirements)
# Arguments:
#   $1 - File path
# Returns: 0 on success, 1 on failure
validate_skill() {
  local file="$1"

  # Skills must have name and description in frontmatter
  if ! validate_markdown "$file" "name description"; then
    echo -e "${V_RED}SKILL VALIDATION FAILED:${V_NC} $file must have 'name' and 'description' in frontmatter" >&2
    return 1
  fi

  # Check that the skill isn't too long (warn at 500+ lines)
  local line_count
  line_count=$(wc -l < "$file" | tr -d ' ')

  if [ "$line_count" -gt 500 ]; then
    echo -e "${V_YELLOW}WARNING:${V_NC} Skill $file is $line_count lines (recommend <500). Consider splitting into reference files." >&2
  fi

  return 0
}

# ============================================================================
# Shell Script Validation
# ============================================================================

# Validate shell script syntax
# Arguments:
#   $1 - File path
# Returns: 0 on success, 1 on failure
validate_shell() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo -e "${V_RED}ERROR:${V_NC} File not found: $file" >&2
    return 1
  fi

  # Basic syntax check with bash -n
  local error_output
  if ! error_output=$(bash -n "$file" 2>&1); then
    echo -e "${V_RED}SHELL VALIDATION FAILED:${V_NC} $file" >&2
    echo "$error_output" >&2
    log_hook_event "Validation" "validate-artifacts" "failed" \
      "$(json_obj "file" "$file" "type" "shell" "error" "$error_output")" 2>/dev/null || true
    return 1
  fi

  # Try shellcheck if available
  if command -v shellcheck &>/dev/null; then
    local shellcheck_output
    if ! shellcheck_output=$(shellcheck "$file" 2>&1); then
      echo -e "${V_YELLOW}SHELLCHECK WARNINGS:${V_NC} $file" >&2
      echo "$shellcheck_output" >&2
      # Don't fail on shellcheck warnings, just report
    fi
  fi

  echo -e "${V_GREEN}Shell script valid:${V_NC} $file" >&2
  return 0
}

# ============================================================================
# Auto-detect and Validate
# ============================================================================

# Automatically detect file type and validate
# Arguments:
#   $1 - File path
# Returns: 0 on success, 1 on failure
validate_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo -e "${V_RED}ERROR:${V_NC} File not found: $file" >&2
    return 1
  fi

  local filename
  filename=$(basename "$file")
  local extension="${filename##*.}"

  case "$extension" in
    json)
      validate_json "$file"
      ;;
    yaml|yml)
      validate_yaml "$file"
      ;;
    md)
      if [[ "$filename" == "SKILL.md" ]]; then
        validate_skill "$file"
      else
        validate_markdown "$file"
      fi
      ;;
    sh|bash)
      validate_shell "$file"
      ;;
    *)
      # Check shebang for shell scripts without extension
      local first_line
      first_line=$(head -1 "$file" 2>/dev/null || echo "")
      if [[ "$first_line" == "#!/"*"bash"* ]] || [[ "$first_line" == "#!/"*"sh"* ]]; then
        validate_shell "$file"
      else
        echo -e "${V_YELLOW}NOTE:${V_NC} Unknown file type, skipping validation: $file" >&2
      fi
      ;;
  esac
}

# Validate multiple files
# Arguments:
#   $@ - File paths
# Returns: Number of failures
validate_files() {
  local failures=0

  for file in "$@"; do
    if ! validate_file "$file"; then
      failures=$((failures + 1))
    fi
  done

  return $failures
}

# ============================================================================
# Hooks Integration Helpers
# ============================================================================

# Get file extension
# Arguments:
#   $1 - File path
get_extension() {
  local file="$1"
  local filename
  filename=$(basename "$file")
  echo "${filename##*.}"
}

# Check if file should be validated
# Arguments:
#   $1 - File path
# Returns: 0 if should validate, 1 if should skip
should_validate() {
  local file="$1"

  # Skip if file doesn't exist
  [ -f "$file" ] || return 1

  local ext
  ext=$(get_extension "$file")

  case "$ext" in
    json|yaml|yml|md|sh|bash)
      return 0
      ;;
    *)
      # Check shebang
      local first_line
      first_line=$(head -1 "$file" 2>/dev/null || echo "")
      if [[ "$first_line" == "#!/"*"bash"* ]] || [[ "$first_line" == "#!/"*"sh"* ]]; then
        return 0
      fi
      return 1
      ;;
  esac
}

# Format validation result as JSON for hook output
# Arguments:
#   $1 - File path
#   $2 - Validation result (pass/fail)
#   $3 - Error message (optional)
format_validation_result() {
  local file="$1"
  local result="$2"
  local error="${3:-}"

  if [ -n "$error" ]; then
    json_obj "file" "$file" "result" "$result" "error" "$error"
  else
    json_obj "file" "$file" "result" "$result"
  fi
}
