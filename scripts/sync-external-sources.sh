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
SOURCE_REPO="anthropics/claude-plugins-official"
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
# Format: "source_path:dest_subdir:type"
# type: agent|skill
declare -a SYNC_ITEMS=(
  # pr-review-toolkit agents
  "plugins/pr-review-toolkit/agents/silent-failure-hunter.md:agents:agent"
  "plugins/pr-review-toolkit/agents/pr-test-analyzer.md:agents:agent"
  "plugins/pr-review-toolkit/agents/type-design-analyzer.md:agents:agent"
  "plugins/pr-review-toolkit/agents/code-simplifier.md:agents:agent"
  "plugins/pr-review-toolkit/agents/comment-analyzer.md:agents:agent"

  # feature-dev agents
  "plugins/feature-dev/agents/code-architect.md:agents:agent"
  "plugins/feature-dev/agents/code-explorer.md:agents:agent"

  # plugin-dev skills (directories)
  "plugins/plugin-dev/skills/skill-development:skills:skill"
  "plugins/plugin-dev/skills/hook-development:skills:skill"
  "plugins/plugin-dev/skills/agent-development:skills:skill"
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

# Get latest commit hash from source repo
get_source_commit() {
  gh api "repos/${SOURCE_REPO}/commits/main" --jq '.sha' 2>/dev/null
}

# Fetch a file from the source repo
fetch_file() {
  local path="$1"
  local dest="$2"

  log_verbose "Fetching: $path -> $dest"

  if [ "$DRY_RUN" = true ]; then
    echo "  Would fetch: $path"
    return 0
  fi

  local content
  content=$(gh api "repos/${SOURCE_REPO}/contents/${path}" --jq '.content' 2>/dev/null)

  if [ -z "$content" ] || [ "$content" = "null" ]; then
    log_warn "Could not fetch: $path (may be a directory)"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"
  echo "$content" | base64 -d > "$dest"
  log_verbose "Saved: $dest"
}

# Fetch a directory recursively from the source repo
fetch_directory() {
  local path="$1"
  local dest="$2"

  log_verbose "Fetching directory: $path -> $dest"

  if [ "$DRY_RUN" = true ]; then
    echo "  Would fetch directory: $path"
    return 0
  fi

  mkdir -p "$dest"

  # Get directory contents
  local items
  items=$(gh api "repos/${SOURCE_REPO}/contents/${path}" 2>/dev/null)

  if [ -z "$items" ] || [ "$items" = "null" ]; then
    log_warn "Could not list: $path"
    return 1
  fi

  # Process each item
  echo "$items" | jq -r '.[] | "\(.type)|\(.name)|\(.path)"' | while IFS='|' read -r type name item_path; do
    if [ "$type" = "file" ]; then
      fetch_file "$item_path" "${dest}/${name}"
    elif [ "$type" = "dir" ]; then
      fetch_directory "$item_path" "${dest}/${name}"
    fi
  done
}

# Add attribution header to agent files
add_attribution_header() {
  local file="$1"
  local source_path="$2"

  if [ "$DRY_RUN" = true ]; then
    return 0
  fi

  if [ ! -f "$file" ]; then
    return 0
  fi

  # Check if file already has attribution
  if grep -q "SOURCE: ${SOURCE_REPO}" "$file" 2>/dev/null; then
    log_verbose "Attribution already present: $file"
    return 0
  fi

  # Read file content
  local content
  content=$(cat "$file")

  # Attribution block
  local attribution="# SOURCE: ${SOURCE_REPO}
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
  local commit_hash="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$DRY_RUN" = true ]; then
    echo "Would write metadata to: $METADATA_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$METADATA_FILE")"

  # Build synced paths array
  local paths_json="["
  local first=true
  for item in "${SYNC_ITEMS[@]}"; do
    IFS=':' read -r source_path dest_subdir item_type <<< "$item"
    if [ "$first" = true ]; then
      first=false
    else
      paths_json+=","
    fi
    paths_json+="\"${source_path}\""
  done
  paths_json+="]"

  cat > "$METADATA_FILE" << EOF
{
  "source_repo": "${SOURCE_REPO}",
  "last_sync": "${timestamp}",
  "commit_hash": "${commit_hash}",
  "synced_paths": ${paths_json}
}
EOF

  log_success "Metadata written: $METADATA_FILE"
}

# Main sync function
sync_all() {
  log_info "Syncing from ${SOURCE_REPO}..."

  # Get current commit
  local commit_hash
  commit_hash=$(get_source_commit)

  if [ -z "$commit_hash" ]; then
    log_error "Could not get source repository commit hash"
    exit 1
  fi

  log_info "Source commit: ${commit_hash:0:8}"

  # Check if already synced
  if [ -f "$METADATA_FILE" ] && [ "$DRY_RUN" = false ]; then
    local last_commit
    last_commit=$(jq -r '.commit_hash' "$METADATA_FILE" 2>/dev/null || echo "")
    if [ "$last_commit" = "$commit_hash" ]; then
      log_success "Already up to date (${commit_hash:0:8})"
      exit 0
    fi
    log_info "Updating from ${last_commit:0:8} to ${commit_hash:0:8}"
  fi

  # Create external directory
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "${EXTERNAL_DIR}/agents"
    mkdir -p "${EXTERNAL_DIR}/skills"
  fi

  # Process each sync item
  local synced_count=0
  for item in "${SYNC_ITEMS[@]}"; do
    IFS=':' read -r source_path dest_subdir item_type <<< "$item"

    local dest_path="${EXTERNAL_DIR}/${dest_subdir}"
    local basename
    basename=$(basename "$source_path")

    log_info "Syncing: $source_path"

    case $item_type in
      agent)
        if fetch_file "$source_path" "${dest_path}/${basename}"; then
          add_attribution_header "${dest_path}/${basename}" "$source_path"
          ((synced_count++)) || true
        fi
        ;;
      skill)
        if fetch_directory "$source_path" "${dest_path}/${basename}"; then
          # Add attribution to SKILL.md
          add_attribution_header "${dest_path}/${basename}/SKILL.md" "${source_path}/SKILL.md"
          ((synced_count++)) || true
        fi
        ;;
    esac
  done

  # Write metadata
  write_metadata "$commit_hash"

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
