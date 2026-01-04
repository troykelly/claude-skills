#!/usr/bin/env bash
# Issue-Driven Development Plugin - Session Start Hook
# Validates environment and checks dependencies

set -euo pipefail

# Source logging utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/log-event.sh" ]; then
  source "$SCRIPT_DIR/lib/log-event.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output goes to stderr so it appears in Claude Code
exec 1>&2

echo -e "${BLUE}[issue-driven-development]${NC} Validating environment..."

log_hook_event "SessionStart" "session-start" "started" "{}"

WARNINGS=()
ERRORS=()

# Check required CLI tools
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 available"
        return 0
    else
        ERRORS+=("$1 is required but not installed")
        echo -e "  ${RED}✗${NC} $1 not found"
        return 1
    fi
}

# Check optional CLI tools
check_optional() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 available"
        return 0
    else
        WARNINGS+=("$1 is recommended but not installed")
        echo -e "  ${YELLOW}!${NC} $1 not found (optional)"
        return 1
    fi
}

echo ""
echo "Checking required tools..."
check_command "git" || true
check_command "gh" || true

echo ""
echo "Checking optional tools..."
check_optional "node" || true
check_optional "pnpm" || true
check_optional "uvx" || true

# Check gh authentication
echo ""
echo "Checking GitHub CLI authentication..."
if command -v gh &> /dev/null; then
    if gh auth status &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} GitHub CLI authenticated"
    else
        ERRORS+=("GitHub CLI not authenticated - run 'gh auth login'")
        echo -e "  ${RED}✗${NC} GitHub CLI not authenticated"
    fi
fi

# Check environment variables
echo ""
echo "Checking environment variables..."

if [ -n "${GITHUB_PROJECT:-}" ]; then
    echo -e "  ${GREEN}✓${NC} GITHUB_PROJECT is set"
else
    WARNINGS+=("GITHUB_PROJECT not set - required for issue tracking")
    echo -e "  ${YELLOW}!${NC} GITHUB_PROJECT not set"
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo -e "  ${GREEN}✓${NC} GITHUB_TOKEN is set"
else
    WARNINGS+=("GITHUB_TOKEN not set - required for GitHub MCP server")
    echo -e "  ${YELLOW}!${NC} GITHUB_TOKEN not set"
fi

# Check Claude account status (multi-account support)
echo ""
echo "Checking Claude account status..."

# Find claude-account script
CLAUDE_ACCOUNT=""
if [ -x "$SCRIPT_DIR/../scripts/claude-account" ]; then
    CLAUDE_ACCOUNT="$SCRIPT_DIR/../scripts/claude-account"
elif command -v claude-account &> /dev/null; then
    CLAUDE_ACCOUNT="claude-account"
fi

if [ -n "$CLAUDE_ACCOUNT" ]; then
    # Get current account
    CURRENT_ACCOUNT=$("$CLAUDE_ACCOUNT" current 2>/dev/null || echo "")

    if [ -n "$CURRENT_ACCOUNT" ]; then
        echo -e "  ${GREEN}✓${NC} Current account: ${CURRENT_ACCOUNT}"

        # Get all accounts and available accounts
        ALL_ACCOUNTS=$("$CLAUDE_ACCOUNT" list 2>/dev/null || echo "")
        AVAILABLE_ACCOUNTS=$("$CLAUDE_ACCOUNT" list --available 2>/dev/null || echo "")

        # Count accounts
        TOTAL_COUNT=$(echo "$ALL_ACCOUNTS" | grep -c '@' 2>/dev/null || echo "0")
        AVAILABLE_COUNT=$(echo "$AVAILABLE_ACCOUNTS" | grep -c '@' 2>/dev/null || echo "0")

        if [ "$TOTAL_COUNT" -gt 1 ]; then
            echo -e "  ${GREEN}✓${NC} Multi-account switching: enabled"
            echo -e "  ${BLUE}│${NC} Total accounts: ${TOTAL_COUNT}"

            if [ "$AVAILABLE_COUNT" -gt 0 ]; then
                echo -e "  ${BLUE}│${NC} Available (not exhausted): ${AVAILABLE_COUNT}"
            fi

            # Show switch order (accounts other than current)
            echo ""
            echo -e "  ${BLUE}Account switch order:${NC}"
            SWITCH_ORDER=""
            FOUND_CURRENT=false

            # First pass: accounts after current
            while IFS= read -r account; do
                [ -z "$account" ] && continue
                if [ "$FOUND_CURRENT" = "true" ]; then
                    if [ -n "$SWITCH_ORDER" ]; then
                        SWITCH_ORDER="$SWITCH_ORDER → $account"
                    else
                        SWITCH_ORDER="$account"
                    fi
                fi
                if [ "$account" = "$CURRENT_ACCOUNT" ]; then
                    FOUND_CURRENT=true
                fi
            done <<< "$ALL_ACCOUNTS"

            # Second pass: accounts before current (wrap around)
            while IFS= read -r account; do
                [ -z "$account" ] && continue
                if [ "$account" = "$CURRENT_ACCOUNT" ]; then
                    break
                fi
                if [ -n "$SWITCH_ORDER" ]; then
                    SWITCH_ORDER="$SWITCH_ORDER → $account"
                else
                    SWITCH_ORDER="$account"
                fi
            done <<< "$ALL_ACCOUNTS"

            if [ -n "$SWITCH_ORDER" ]; then
                echo -e "    ${CURRENT_ACCOUNT} (current)"
                echo -e "    → ${SWITCH_ORDER}"
            fi

            # Show exhaustion status if any accounts are exhausted
            EXHAUSTED_COUNT=$((TOTAL_COUNT - AVAILABLE_COUNT))
            if [ "$EXHAUSTED_COUNT" -gt 0 ] && [ "$AVAILABLE_COUNT" -lt "$TOTAL_COUNT" ]; then
                echo ""
                echo -e "  ${YELLOW}!${NC} ${EXHAUSTED_COUNT} account(s) in cooldown"
                WARNINGS+=("Some accounts are in cooldown from plan limits")
            fi
        else
            echo -e "  ${YELLOW}○${NC} Single account mode (no switching available)"
        fi
    else
        echo -e "  ${YELLOW}!${NC} No Claude account detected"
        WARNINGS+=("Could not detect current Claude account")
    fi
else
    echo -e "  ${RED}✗${NC} claude-account script not found"
    echo -e "  ${BLUE}│${NC} Multi-account switching: disabled"
    echo -e "  ${BLUE}│${NC} Install: Add scripts/claude-account to PATH or install plugin"
    WARNINGS+=("claude-account not available - multi-account switching disabled")
fi

# Check MCP server dependencies
echo ""
echo "Checking MCP server dependencies..."

# Git MCP server (Python)
if command -v uvx &> /dev/null || python3 -c "import mcp_server_git" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Git MCP server available"
else
    WARNINGS+=("Git MCP server not installed - run 'pip install mcp-server-git'")
    echo -e "  ${YELLOW}!${NC} Git MCP server not installed"
fi

# Node-based MCP servers
if command -v npx &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} npx available for Node MCP servers"
else
    WARNINGS+=("npx not available - Node MCP servers may not work")
    echo -e "  ${YELLOW}!${NC} npx not available"
fi

# Check development services (docker-compose)
echo ""
echo "Checking development services..."

COMPOSE_FILE=""
if [ -f "docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
elif [ -f "docker-compose.yaml" ]; then
    COMPOSE_FILE="docker-compose.yaml"
elif [ -f ".devcontainer/docker-compose.yml" ]; then
    COMPOSE_FILE=".devcontainer/docker-compose.yml"
elif [ -f ".devcontainer/docker-compose.yaml" ]; then
    COMPOSE_FILE=".devcontainer/docker-compose.yaml"
fi

if [ -n "$COMPOSE_FILE" ]; then
    echo -e "  ${GREEN}✓${NC} Found $COMPOSE_FILE"

    if command -v docker-compose &> /dev/null; then
        # List services and their status
        SERVICES=$(docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null || echo "")

        if [ -n "$SERVICES" ]; then
            echo ""
            echo "  Available services:"
            for service in $SERVICES; do
                if docker-compose -f "$COMPOSE_FILE" ps "$service" 2>/dev/null | grep -q "Up"; then
                    echo -e "    ${GREEN}✓${NC} $service (running)"
                else
                    echo -e "    ${YELLOW}○${NC} $service (not running)"
                    WARNINGS+=("Service '$service' is available but not running - run 'docker-compose up -d $service'")
                fi
            done
            echo ""
            echo -e "  ${BLUE}Tip:${NC} Start services with: docker-compose -f $COMPOSE_FILE up -d"
        fi
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        # Try docker compose (v2) instead
        SERVICES=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null || echo "")

        if [ -n "$SERVICES" ]; then
            echo ""
            echo "  Available services:"
            for service in $SERVICES; do
                if docker compose -f "$COMPOSE_FILE" ps "$service" 2>/dev/null | grep -q "running"; then
                    echo -e "    ${GREEN}✓${NC} $service (running)"
                else
                    echo -e "    ${YELLOW}○${NC} $service (not running)"
                    WARNINGS+=("Service '$service' is available but not running - run 'docker compose up -d $service'")
                fi
            done
            echo ""
            echo -e "  ${BLUE}Tip:${NC} Start services with: docker compose -f $COMPOSE_FILE up -d"
        fi
    else
        WARNINGS+=("docker-compose not available - cannot check service status")
        echo -e "  ${YELLOW}!${NC} docker-compose not available"
    fi
else
    echo -e "  ${YELLOW}○${NC} No docker-compose.yml found (no local services)"
fi

# Summary
echo ""
echo -e "${BLUE}[issue-driven-development]${NC} Environment check complete"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}ERRORS (must fix):${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "  ${RED}•${NC} $err"
    done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}WARNINGS (recommended):${NC}"
    for warn in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}•${NC} $warn"
    done
fi

if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    log_hook_event "SessionStart" "session-start" "completed" '{"status": "all_passed"}'
else
    log_hook_event "SessionStart" "session-start" "completed" \
      "{\"errors\": ${#ERRORS[@]}, \"warnings\": ${#WARNINGS[@]}}"
fi

echo ""
echo -e "${BLUE}Remember:${NC} Use 'issue-driven-development' skill for all work."
echo ""

# Always exit 0 - we don't want to block Claude, just inform
exit 0
