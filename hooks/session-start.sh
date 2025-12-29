#!/usr/bin/env bash
# Issue-Driven Development Plugin - Session Start Hook
# Validates environment and checks dependencies

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output goes to stderr so it appears in Claude Code
exec 1>&2

echo -e "${BLUE}[issue-driven-development]${NC} Validating environment..."

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
check_optional "npm" || true
check_optional "npx" || true
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
fi

echo ""
echo -e "${BLUE}Remember:${NC} Use 'issue-driven-development' skill for all work."
echo ""

# Always exit 0 - we don't want to block Claude, just inform
exit 0
