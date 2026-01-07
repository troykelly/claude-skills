#!/usr/bin/env bash
#
# sync-external-sources.sh
#
# Syncs skills and agents from anthropics/claude-plugins-official
# to the external/ directory of this plugin.
#
# Usage:
#   ./scripts/sync-external-sources.sh [--dry-run] [--verbose]
#
# Options:
#   --dry-run    Show what would be synced without making changes
#   --verbose    Show detailed progress
#
# Source: anthropics/claude-plugins-official
# Documentation: See EXTERNAL_SOURCES.md for full details

set -euo pipefail

# Configuration
DEFAULT_SOURCE_REPO="anthropics/claude-plugins-official"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXTERNAL_DIR="${PROJECT_ROOT}/external"
METADATA_FILE="${EXTERNAL_DIR}/.sync-metadata.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
VERBOSE=false
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      ;;
    --verbose)
      VERBOSE=true
      ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      echo "Usage: $0 [--dry-run] [--verbose]"
      exit 1
      ;;
  esac
done

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo -e "${BLUE}[VERBOSE]${NC} $1"
  fi
}

# Artifacts to sync
# Format: "repo:source_path:dest_subdir:type"
# repo: GitHub owner/repo (use DEFAULT for anthropics/claude-plugins-official)
# type: agent|skill
declare -a SYNC_ITEMS=(
  # pr-review-toolkit agents (from anthropics/claude-plugins-official)
  "DEFAULT:plugins/pr-review-toolkit/agents/silent-failure-hunter.md:agents:agent"
  "DEFAULT:plugins/pr-review-toolkit/agents/pr-test-analyzer.md:agents:agent"
  "DEFAULT:plugins/pr-review-toolkit/agents/type-design-analyzer.md:agents:agent"
  "DEFAULT:plugins/pr-review-toolkit/agents/code-simplifier.md:agents:agent"
  "DEFAULT:plugins/pr-review-toolkit/agents/comment-analyzer.md:agents:agent"

  # feature-dev agents (from anthropics/claude-plugins-official)
  "DEFAULT:plugins/feature-dev/agents/code-architect.md:agents:agent"
  "DEFAULT:plugins/feature-dev/agents/code-explorer.md:agents:agent"

  # plugin-dev skills (from anthropics/claude-plugins-official)
  "DEFAULT:plugins/plugin-dev/skills/skill-development:skills:skill"
  "DEFAULT:plugins/plugin-dev/skills/hook-development:skills:skill"
  "DEFAULT:plugins/plugin-dev/skills/agent-development:skills:skill"

  # frontend-design skill (from anthropics/claude-plugins-official)
  "DEFAULT:plugins/frontend-design/skills/frontend-design:skills:skill"

  # Sentry skills (from getsentry/sentry-for-claude)
  "getsentry/sentry-for-claude:skills/sentry-code-review:skills:skill"
  "getsentry/sentry-for-claude:skills/sentry-setup-ai-monitoring:skills:skill"
  "getsentry/sentry-for-claude:skills/sentry-setup-logging:skills:skill"
  "getsentry/sentry-for-claude:skills/sentry-setup-metrics:skills:skill"
  "getsentry/sentry-for-claude:skills/sentry-setup-tracing:skills:skill"
)

# Check requirements
check_requirements() {
  log_info "Checking requirements..."

  if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is required but not installed"
    exit 1
  fi

  if ! gh auth status &> /dev/null; then
    log_error "GitHub CLI is not authenticated. Run 'gh auth login'"
    exit 1
  fi

  log_success "Requirements satisfied"
}

# Resolve repo name (DEFAULT -> default repo)
resolve_repo() {
  local repo="$1"
  if [ "$repo" = "DEFAULT" ]; then
    echo "$DEFAULT_SOURCE_REPO"
  else
    echo "$repo"
  fi
}

# Fetch a file from a repo
fetch_file() {
  local repo="$1"
  local path="$2"
  local dest="$3"

  repo=$(resolve_repo "$repo")
  log_verbose "Fetching: ${repo}:${path} -> $dest"

  if [ "$DRY_RUN" = true ]; then
    echo "  Would fetch: ${repo}:${path}"
    return 0
  fi

  local content
  content=$(gh api "repos/${repo}/contents/${path}" --jq '.content' 2>/dev/null)

  if [ -z "$content" ] || [ "$content" = "null" ]; then
    log_warn "Could not fetch: ${repo}:${path} (may be a directory)"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"
  echo "$content" | base64 -d > "$dest"
  log_verbose "Saved: $dest"
}

# Fetch a directory recursively from a repo
fetch_directory() {
  local repo="$1"
  local path="$2"
  local dest="$3"

  repo=$(resolve_repo "$repo")
  log_verbose "Fetching directory: ${repo}:${path} -> $dest"

  if [ "$DRY_RUN" = true ]; then
    echo "  Would fetch directory: ${repo}:${path}"
    return 0
  fi

  mkdir -p "$dest"

  # Get directory contents
  local items
  items=$(gh api "repos/${repo}/contents/${path}" 2>/dev/null)

  if [ -z "$items" ] || [ "$items" = "null" ]; then
    log_warn "Could not list: ${repo}:${path}"
    return 1
  fi

  # Process each item (pass repo through for recursive calls)
  local resolved_repo="$repo"
  echo "$items" | jq -r '.[] | "\(.type)|\(.name)|\(.path)"' | while IFS='|' read -r type name item_path; do
    if [ "$type" = "file" ]; then
      fetch_file "$resolved_repo" "$item_path" "${dest}/${name}"
    elif [ "$type" = "dir" ]; then
      fetch_directory "$resolved_repo" "$item_path" "${dest}/${name}"
    fi
  done
}

# Add attribution header to agent files
add_attribution_header() {
  local file="$1"
  local repo="$2"
  local source_path="$3"

  repo=$(resolve_repo "$repo")

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  if [ ! -f "$file" ]; then
    return 0
  fi

  # Check if file already has attribution (check for any SOURCE: line)
  if grep -q "^# SOURCE:" "$file" 2>/dev/null; then
    log_verbose "Attribution already present: $file"
    return 0
  fi

  # Read file content
  local content
  content=$(cat "$file")

  # Attribution block
  local attribution="# SOURCE: ${repo}
# PATH: ${source_path}
# DO NOT EDIT: This file is synced from external source
"

  # Check if it starts with frontmatter
  if [[ "$content" == "---"* ]]; then
    # Insert attribution AFTER the closing --- of frontmatter
    local rest="${content#---}"

    # Find end of frontmatter (second ---)
    local frontmatter="${rest%%---*}"
    local after_frontmatter="${rest#*---}"

    cat > "$file" << EOF
---${frontmatter}---

${attribution}${after_frontmatter}
EOF
  else
    # Add header at top
    cat > "$file" << EOF
${attribution}
${content}
EOF
  fi

  log_verbose "Added attribution: $file"
}

# Write sync metadata
write_metadata() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DRY_RUN" = true ]; then
    echo "Would write metadata to: $METADATA_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$METADATA_FILE")"

  # Build synced items array with full details
  local items_json="["
  local first=true
  for item in "${SYNC_ITEMS[@]}"; do
    IFS=':' read -r repo source_path dest_subdir item_type <<< "$item"
    repo=$(resolve_repo "$repo")
    if [ "$first" = true ]; then
      first=false
    else
      items_json+=","
    fi
    items_json+="{\"repo\":\"${repo}\",\"path\":\"${source_path}\",\"type\":\"${item_type}\"}"
  done
  items_json+="]"

  cat > "$METADATA_FILE" << EOF
{
  "last_sync": "${timestamp}",
  "synced_items": ${items_json}
}
EOF

  log_success "Metadata written: $METADATA_FILE"
}

# Main sync function
sync_all() {
  log_info "Syncing external skills and agents..."

  # Create external directory
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "${EXTERNAL_DIR}/agents"
    mkdir -p "${EXTERNAL_DIR}/skills"
  fi

  # Process each sync item
  local synced_count=0
  for item in "${SYNC_ITEMS[@]}"; do
    IFS=':' read -r repo source_path dest_subdir item_type <<< "$item"

    local resolved_repo
    resolved_repo=$(resolve_repo "$repo")

    local dest_path="${EXTERNAL_DIR}/${dest_subdir}"
    local basename
    basename=$(basename "$source_path")

    log_info "Syncing: ${resolved_repo}:${source_path}"

    case $item_type in
      agent)
        if fetch_file "$repo" "$source_path" "${dest_path}/${basename}"; then
          add_attribution_header "${dest_path}/${basename}" "$repo" "$source_path"
          ((synced_count++)) || true
        fi
        ;;
      skill)
        if fetch_directory "$repo" "$source_path" "${dest_path}/${basename}"; then
          # Add attribution to SKILL.md
          add_attribution_header "${dest_path}/${basename}/SKILL.md" "$repo" "${source_path}/SKILL.md"
          ((synced_count++)) || true
        fi
        ;;
    esac
  done

  # Write metadata
  write_metadata

  if [ "$DRY_RUN" = true ]; then
    log_info "Dry run complete. No changes made."
  else
    log_success "Sync complete! Synced $synced_count items."
  fi
}

# Run
check_requirements
sync_all

echo ""
log_info "Remember to update plugin.json to include external agents if needed."
log_info "See EXTERNAL_SOURCES.md for integration details."
