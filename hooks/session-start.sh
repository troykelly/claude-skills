#!/usr/bin/env bash
# Issue-Driven Development Plugin - Session Start Hook
# Validates environment and checks dependencies (quiet mode - only shows issues)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib/log-event.sh" ] && source "$SCRIPT_DIR/lib/log-event.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

exec 1>&2

log_hook_event "SessionStart" "session-start" "started" "{}"

WARNINGS=()
ERRORS=()

# Check required CLI tools (silent on success)
check_command() {
    if ! command -v "$1" &> /dev/null; then
        ERRORS+=("$1 is required but not installed")
    fi
}

# Check optional CLI tools (silent on success)
check_optional() {
    if ! command -v "$1" &> /dev/null; then
        WARNINGS+=("$1 is recommended but not installed")
    fi
}

# Required tools
check_command "git"
check_command "gh"

# Optional tools
check_optional "node"
check_optional "pnpm"
check_optional "uvx"

# Check gh authentication
if command -v gh &> /dev/null && ! gh auth status &> /dev/null; then
    ERRORS+=("GitHub CLI not authenticated - run 'gh auth login'")
fi

# Check environment variables
[ -z "${GITHUB_PROJECT:-}" ] && WARNINGS+=("GITHUB_PROJECT not set")
[ -z "${GITHUB_TOKEN:-}" ] && WARNINGS+=("GITHUB_TOKEN not set")

# Check Claude account status (compact output)
CLAUDE_ACCOUNT=""
[ -x "$SCRIPT_DIR/../scripts/claude-account" ] && CLAUDE_ACCOUNT="$SCRIPT_DIR/../scripts/claude-account"
[ -z "$CLAUDE_ACCOUNT" ] && command -v claude-account &> /dev/null && CLAUDE_ACCOUNT="claude-account"

ACCOUNT_INFO=""
if [ -n "$CLAUDE_ACCOUNT" ]; then
    CURRENT_OUTPUT=$("$CLAUDE_ACCOUNT" current 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g') || CURRENT_OUTPUT=""
    CURRENT_ACCOUNT=$(echo "$CURRENT_OUTPUT" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1) || true

    if [ -n "$CURRENT_ACCOUNT" ]; then
        AVAILABLE_ACCOUNTS=$("$CLAUDE_ACCOUNT" list --available 2>/dev/null) || AVAILABLE_ACCOUNTS=""
        AVAILABLE_COUNT=$(echo "$AVAILABLE_ACCOUNTS" | grep -c '@') || AVAILABLE_COUNT=0

        LIST_OUTPUT=$("$CLAUDE_ACCOUNT" list 2>/dev/null) || LIST_OUTPUT=""
        TOTAL_COUNT=$(echo "$LIST_OUTPUT" | grep "^Total:" | grep -oE '[0-9]+' | head -1) || TOTAL_COUNT="$AVAILABLE_COUNT"
        [ -z "$TOTAL_COUNT" ] && TOTAL_COUNT="$AVAILABLE_COUNT"

        EXHAUSTED_COUNT=$((TOTAL_COUNT - AVAILABLE_COUNT))

        if [ "$TOTAL_COUNT" -gt 1 ]; then
            ACCOUNT_INFO="$CURRENT_ACCOUNT ($AVAILABLE_COUNT/$TOTAL_COUNT available)"
            [ "$EXHAUSTED_COUNT" -gt 0 ] && WARNINGS+=("$EXHAUSTED_COUNT account(s) in cooldown")
        else
            ACCOUNT_INFO="$CURRENT_ACCOUNT (single account)"
        fi
    fi
fi

# Check MCP dependencies (silent on success)
if ! command -v uvx &> /dev/null && ! python3 -c "import mcp_server_git" 2>/dev/null; then
    WARNINGS+=("Git MCP server not installed")
fi
! command -v npx &> /dev/null && WARNINGS+=("npx not available for Node MCP servers")

# Output - compact summary only
echo -e "${BLUE}[issue-driven-development]${NC} Session started"

# Show account info if available
[ -n "$ACCOUNT_INFO" ] && echo -e "  Account: $ACCOUNT_INFO"

# Show errors
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}Errors:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "  ${RED}•${NC} $err"
    done
fi

# Show warnings (condensed)
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warnings:${NC} ${WARNINGS[*]}"
fi

# Log completion
if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    log_hook_event "SessionStart" "session-start" "completed" '{"status": "all_passed"}'
else
    log_hook_event "SessionStart" "session-start" "completed" \
      "{\"errors\": ${#ERRORS[@]}, \"warnings\": ${#WARNINGS[@]}}"
fi

exit 0
