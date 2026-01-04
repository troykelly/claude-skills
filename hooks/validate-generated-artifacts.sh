#!/usr/bin/env bash
#
# validate-generated-artifacts.sh - PostToolUse hook to validate generated files
#
# Validates JSON, YAML, Markdown, and shell scripts after Write/Edit operations.
# Uses the validate-artifacts.sh library for validation logic.
#
# Input: JSON via stdin with tool_input.file_path (PostToolUse hook format)
# Output: JSON status to stdout, error details if validation fails
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the validation library
if [[ -f "$SCRIPT_DIR/lib/validate-artifacts.sh" ]]; then
  source "$SCRIPT_DIR/lib/validate-artifacts.sh"
else
  # Library not available - skip validation silently
  exit 0
fi

# Read hook input from stdin (PostToolUse hook JSON format)
HOOK_INPUT=$(cat)

# Extract file path from tool_input (Write/Edit tools use file_path)
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -z "$FILE_PATH" ]]; then
  # No file path in result - skip
  exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
  # File doesn't exist - skip (might be a delete operation)
  exit 0
fi

# Determine file type and validate
EXT="${FILE_PATH##*.}"
FILENAME=$(basename "$FILE_PATH")

# Output function for structured logging
output_result() {
  local status="$1"
  local details="${2:-}"

  cat <<EOF
{"event": "PostToolUse", "hook": "validate-generated-artifacts", "file": "$FILE_PATH", "status": "$status", "details": "$details"}
EOF
}

# Validate based on file type
case "$EXT" in
  json)
    if validate_json "$FILE_PATH" 2>/dev/null; then
      output_result "valid"
    else
      output_result "invalid" "JSON validation failed - check syntax"
      echo "WARNING: Generated JSON file has syntax errors: $FILE_PATH" >&2
    fi
    ;;

  yaml|yml)
    if validate_yaml "$FILE_PATH" 2>/dev/null; then
      output_result "valid"
    else
      output_result "invalid" "YAML validation failed - check syntax"
      echo "WARNING: Generated YAML file has syntax errors: $FILE_PATH" >&2
    fi
    ;;

  md)
    # For skill files, use skill validation
    if [[ "$FILE_PATH" == *"/skills/"* && "$FILENAME" == "SKILL.md" ]]; then
      if validate_skill "$FILE_PATH" 2>/dev/null; then
        output_result "valid"
      else
        output_result "invalid" "Skill validation failed - check frontmatter"
        echo "WARNING: Skill file missing required frontmatter: $FILE_PATH" >&2
      fi
    else
      # Regular markdown - basic validation
      if validate_markdown "$FILE_PATH" 2>/dev/null; then
        output_result "valid"
      else
        output_result "warning" "Markdown validation warning"
      fi
    fi
    ;;

  sh|bash)
    if validate_shell "$FILE_PATH" 2>/dev/null; then
      output_result "valid"
    else
      output_result "invalid" "Shell script has syntax errors"
      echo "WARNING: Generated shell script has syntax errors: $FILE_PATH" >&2
    fi
    ;;

  *)
    # Unknown file type - skip validation
    output_result "skipped" "Unknown file type"
    ;;
esac

# Always exit success - validation is advisory, not blocking
exit 0
