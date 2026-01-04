#!/usr/bin/env bash
#
# install.sh - Install claude-autonomous and dependencies
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/troykelly/claude-skills/main/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/troykelly/claude-skills.git
#   cd claude-skills && ./install.sh
#
# Options (via environment variables):
#   INSTALL_DIR     Where to install (default: /usr/local/bin)
#   SKIP_DEPS       Skip dependency installation (default: false)
#   SKIP_PLUGIN     Skip Claude Code plugin installation (default: false)
#   SKIP_PLAYWRIGHT Skip Playwright browser installation (default: false)
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
SKIP_DEPS="${SKIP_DEPS:-false}"
SKIP_PLUGIN="${SKIP_PLUGIN:-false}"
SKIP_PLAYWRIGHT="${SKIP_PLAYWRIGHT:-false}"
REPO_URL="https://github.com/troykelly/claude-skills"
RAW_URL="https://raw.githubusercontent.com/troykelly/claude-skills/main"

# Detect OS and package manager
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    PKG_MGR="brew"
  elif [[ -f /etc/debian_version ]]; then
    OS="debian"
    PKG_MGR="apt"
  elif [[ -f /etc/fedora-release ]]; then
    OS="fedora"
    PKG_MGR="dnf"
  elif [[ -f /etc/redhat-release ]]; then
    OS="redhat"
    # Use dnf if available (RHEL 8+), fall back to yum
    if has_cmd dnf; then
      PKG_MGR="dnf"
    else
      PKG_MGR="yum"
    fi
  elif [[ -f /etc/arch-release ]]; then
    OS="arch"
    PKG_MGR="pacman"
  elif [[ -f /etc/alpine-release ]]; then
    OS="alpine"
    PKG_MGR="apk"
  else
    OS="unknown"
    PKG_MGR="unknown"
  fi
}

# Verify network connectivity
check_connectivity() {
  log_info "Checking network connectivity..."
  if ! curl -fsSL --connect-timeout 5 https://github.com &>/dev/null; then
    log_error "Cannot reach github.com - check your internet connection"
    exit 1
  fi
  log_success "Network connectivity OK"
}

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if command exists
has_cmd() { command -v "$1" &>/dev/null; }

# Run with sudo if needed
maybe_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if has_cmd sudo; then
      sudo "$@"
    else
      log_error "Need root privileges. Please run as root or install sudo."
      exit 1
    fi
  else
    "$@"
  fi
}

# Install package based on package manager
install_pkg() {
  local pkg="$1"
  local pkg_apt="${2:-$pkg}"
  local pkg_yum="${3:-$pkg}"
  local pkg_brew="${4:-$pkg}"
  local pkg_pacman="${5:-$pkg}"
  local pkg_apk="${6:-$pkg}"

  if has_cmd "$pkg"; then
    log_success "$pkg already installed"
    return 0
  fi

  log_info "Installing $pkg..."

  case "$PKG_MGR" in
    apt)
      maybe_sudo apt-get update -qq
      maybe_sudo apt-get install -y -qq "$pkg_apt"
      ;;
    dnf)
      maybe_sudo dnf install -y -q "$pkg_yum"
      ;;
    yum)
      maybe_sudo yum install -y -q "$pkg_yum"
      ;;
    brew)
      brew install "$pkg_brew"
      ;;
    pacman)
      maybe_sudo pacman -S --noconfirm "$pkg_pacman"
      ;;
    apk)
      maybe_sudo apk add --quiet "$pkg_apk"
      ;;
    *)
      log_warn "Unknown package manager. Please install $pkg manually."
      return 1
      ;;
  esac

  if has_cmd "$pkg"; then
    log_success "$pkg installed successfully"
  else
    log_error "Failed to install $pkg"
    return 1
  fi
}

# Install GitHub CLI (special case - needs repo setup on some distros)
install_gh() {
  if has_cmd gh; then
    log_success "gh (GitHub CLI) already installed"
    return 0
  fi

  log_info "Installing GitHub CLI..."

  case "$PKG_MGR" in
    apt)
      # Add GitHub CLI repo
      maybe_sudo mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | maybe_sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
      maybe_sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | maybe_sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      maybe_sudo apt-get update -qq
      maybe_sudo apt-get install -y -qq gh
      ;;
    dnf)
      maybe_sudo dnf install -y -q 'dnf-command(config-manager)' 2>/dev/null || true
      maybe_sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      maybe_sudo dnf install -y -q gh
      ;;
    yum)
      maybe_sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      maybe_sudo yum install -y -q gh
      ;;
    brew)
      brew install gh
      ;;
    pacman)
      maybe_sudo pacman -S --noconfirm github-cli
      ;;
    apk)
      maybe_sudo apk add --quiet github-cli
      ;;
    *)
      log_warn "Please install GitHub CLI manually: https://cli.github.com/"
      return 1
      ;;
  esac

  if has_cmd gh; then
    log_success "GitHub CLI installed successfully"
  else
    log_error "Failed to install GitHub CLI"
    return 1
  fi
}

# Install uv/uvx (Python package runner - used for MCP servers like git)
install_uv() {
  if has_cmd uvx; then
    log_success "uv/uvx already installed ($(uv --version 2>/dev/null || echo 'version unknown'))"
    return 0
  fi

  log_info "Installing uv (Python package manager with uvx)..."

  # Use official uv installer
  curl -LsSf https://astral.sh/uv/install.sh | sh

  # Add to PATH for this session
  if [[ -d "$HOME/.local/bin" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi
  if [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi

  if has_cmd uvx; then
    log_success "uv/uvx installed"
  else
    log_warn "uv installed but uvx not in PATH"
    log_info "Add to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\""
    return 0
  fi
}

# Install Node.js (optional - used for MCP servers like memory, playwright)
install_node() {
  if has_cmd node; then
    log_success "Node.js already installed ($(node --version))"
    return 0
  fi

  log_info "Installing Node.js (optional, for MCP servers)..."

  case "$PKG_MGR" in
    apt)
      # Use NodeSource for recent version
      curl -fsSL https://deb.nodesource.com/setup_20.x | maybe_sudo bash -
      maybe_sudo apt-get install -y -qq nodejs
      ;;
    dnf)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | maybe_sudo bash -
      maybe_sudo dnf install -y -q nodejs
      ;;
    yum)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | maybe_sudo bash -
      maybe_sudo yum install -y -q nodejs
      ;;
    brew)
      brew install node
      ;;
    pacman)
      maybe_sudo pacman -S --noconfirm nodejs npm
      ;;
    apk)
      maybe_sudo apk add --quiet nodejs npm
      ;;
    *)
      log_warn "Please install Node.js manually: https://nodejs.org/"
      return 1
      ;;
  esac

  if has_cmd node; then
    log_success "Node.js installed ($(node --version))"
  fi
}

# Install Playwright and browser dependencies (for MCP Playwright server)
install_playwright() {
  # Ensure Node.js and npx are available first
  if ! has_cmd node; then
    log_warn "Node.js required for Playwright - installing..."
    install_node
  fi

  if ! has_cmd npx; then
    log_warn "npx not found - Node.js installation may be incomplete"
    log_info "Try: npm install -g npx"
    return 1
  fi

  # Check if playwright is already installed globally
  if npx playwright --version &>/dev/null 2>&1; then
    log_success "Playwright already installed ($(npx playwright --version 2>/dev/null || echo 'version unknown'))"
    return 0
  fi

  log_info "Installing Playwright with Chromium browser..."

  # Install playwright package
  if ! npm install -g playwright 2>/dev/null; then
    log_warn "Global npm install failed, trying npx approach..."
  fi

  # Install Chromium browser and system dependencies
  # --with-deps installs both the browser and required system libraries
  log_info "Installing Chromium browser and system dependencies..."

  case "$PKG_MGR" in
    apt|dnf|yum|pacman|apk)
      # Linux needs sudo for system dependency installation
      maybe_sudo npx playwright install --with-deps chromium 2>/dev/null || \
        npx playwright install chromium 2>/dev/null || true
      ;;
    brew)
      # macOS doesn't need sudo for deps
      npx playwright install --with-deps chromium 2>/dev/null || \
        npx playwright install chromium 2>/dev/null || true
      ;;
    *)
      npx playwright install chromium 2>/dev/null || true
      ;;
  esac

  if npx playwright --version &>/dev/null 2>&1; then
    log_success "Playwright installed with Chromium"
  else
    log_warn "Playwright may need manual browser setup: npx playwright install --with-deps chromium"
  fi
}

# Install 1Password CLI (optional - for credential management)
install_1password_cli() {
  if has_cmd op; then
    log_success "1Password CLI already installed ($(op --version 2>/dev/null || echo 'version unknown'))"
    return 0
  fi

  log_info "Installing 1Password CLI (optional, for credential management)..."

  case "$PKG_MGR" in
    apt)
      # Add 1Password GPG key and repository
      maybe_sudo mkdir -p -m 755 /usr/share/keyrings
      curl -sS https://downloads.1password.com/linux/keys/1password.asc | maybe_sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg 2>/dev/null || \
        curl -sS https://downloads.1password.com/linux/keys/1password.asc | maybe_sudo tee /usr/share/keyrings/1password-archive-keyring.gpg > /dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | maybe_sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
      maybe_sudo apt-get update -qq
      maybe_sudo apt-get install -y -qq 1password-cli
      ;;
    dnf)
      # Add 1Password RPM repository for Fedora/RHEL
      maybe_sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
      maybe_sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc" > /etc/yum.repos.d/1password.repo'
      maybe_sudo dnf install -y -q 1password-cli
      ;;
    yum)
      # Add 1Password RPM repository for older RHEL/CentOS
      maybe_sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
      maybe_sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc" > /etc/yum.repos.d/1password.repo'
      maybe_sudo yum install -y -q 1password-cli
      ;;
    brew)
      # macOS - use Homebrew cask
      brew install --cask 1password-cli
      ;;
    pacman)
      # Arch Linux - available in community repo
      maybe_sudo pacman -S --noconfirm 1password-cli
      ;;
    apk)
      # Alpine - need to download binary directly
      log_info "Downloading 1Password CLI binary for Alpine..."
      local arch
      arch=$(uname -m)
      case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
      esac
      curl -sSLo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/v2.24.0/op_linux_${arch}_v2.24.0.zip"
      maybe_sudo unzip -o /tmp/op.zip -d /usr/local/bin op
      maybe_sudo chmod +x /usr/local/bin/op
      rm -f /tmp/op.zip
      ;;
    *)
      log_warn "Please install 1Password CLI manually: https://1password.com/downloads/command-line/"
      return 1
      ;;
  esac

  if has_cmd op; then
    log_success "1Password CLI installed ($(op --version 2>/dev/null || echo 'installed'))"
  else
    log_warn "1Password CLI installation may require manual steps"
    log_info "See: https://1password.com/downloads/command-line/"
  fi
}

# Install Claude Code CLI via official installer
install_claude_code() {
  if has_cmd claude; then
    log_success "Claude Code CLI already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
    return 0
  fi

  log_info "Installing Claude Code CLI via official installer..."

  # Use Anthropic's official install script
  curl -fsSL https://claude.ai/install.sh | bash

  # Add to PATH for this session if installed to ~/.claude/bin
  if [[ -d "$HOME/.claude/bin" ]]; then
    export PATH="$HOME/.claude/bin:$PATH"
  fi

  if has_cmd claude; then
    log_success "Claude Code CLI installed"
  else
    log_warn "Claude Code CLI installed but not in PATH"
    log_info "Add to your shell profile: export PATH=\"\$HOME/.claude/bin:\$PATH\""
    return 0
  fi
}

# Install helper scripts (claude-autonomous, claude-account)
install_scripts() {
  local scripts=("claude-autonomous" "claude-account")

  # Create install dir if needed
  if [[ ! -d "$INSTALL_DIR" ]]; then
    maybe_sudo mkdir -p "$INSTALL_DIR"
  fi

  for script_name in "${scripts[@]}"; do
    local script_url="${RAW_URL}/scripts/${script_name}"
    local install_path="${INSTALL_DIR}/${script_name}"

    log_info "Installing ${script_name} to ${install_path}..."

    # Download or copy script
    if [[ -f "scripts/${script_name}" ]]; then
      # Running from cloned repo
      maybe_sudo cp "scripts/${script_name}" "$install_path"
    else
      # Download from GitHub
      curl -fsSL "$script_url" | maybe_sudo tee "$install_path" > /dev/null
    fi

    maybe_sudo chmod +x "$install_path"

    if [[ -x "$install_path" ]]; then
      log_success "Installed ${script_name} to ${install_path}"
    else
      log_error "Failed to install ${script_name}"
      return 1
    fi
  done
}

# Install Claude Code plugin via settings.json (works non-interactively)
install_plugin() {
  local settings_dir="$HOME/.claude"
  local settings_file="$settings_dir/settings.json"

  log_info "Configuring issue-driven-development plugin..."

  # Create settings directory if needed
  mkdir -p "$settings_dir"

  # Build the plugin configuration
  local plugin_config
  plugin_config=$(cat <<'PLUGIN_JSON'
{
  "extraKnownMarketplaces": {
    "troykelly-skills": {
      "source": {
        "source": "github",
        "repo": "troykelly/claude-skills"
      }
    }
  },
  "enabledPlugins": {
    "issue-driven-development@troykelly-skills": true
  }
}
PLUGIN_JSON
)

  if [[ -f "$settings_file" ]]; then
    # Verify jq is available (should be - we install it)
    if ! has_cmd jq; then
      log_warn "jq not available for settings merge"
      log_info "Add plugin manually: claude /plugin install issue-driven-development@troykelly-skills"
      return 1
    fi

    # Check if existing file is valid JSON
    if ! jq empty "$settings_file" 2>/dev/null; then
      log_warn "Existing settings.json is not valid JSON - backing up and creating new"
      cp "$settings_file" "${settings_file}.bak.$(date +%s)"
      echo "$plugin_config" > "$settings_file"
      log_success "Created new settings.json (backup saved)"
      return 0
    fi

    # Check if plugin is already configured (idempotent check)
    local already_configured
    already_configured=$(jq -r '.enabledPlugins["issue-driven-development@troykelly-skills"] // false' "$settings_file" 2>/dev/null)
    if [[ "$already_configured" == "true" ]]; then
      log_success "Plugin already configured in settings.json"
      return 0
    fi

    # Merge with existing settings using jq
    local existing
    existing=$(cat "$settings_file")

    # Deep merge: existing settings + new plugin config (idempotent - same keys overwrite)
    local merged
    merged=$(echo "$existing" "$plugin_config" | jq -s '
      def deepmerge:
        reduce .[] as $item ({}; . * $item);
      deepmerge
    ' 2>/dev/null)

    if [[ -n "$merged" && "$merged" != "null" ]]; then
      echo "$merged" > "$settings_file"
      log_success "Plugin configuration merged into existing settings.json"
    else
      log_warn "Could not merge settings - adding plugin config manually"
      # Fallback: try to add just the essential fields
      local updated
      updated=$(echo "$existing" | jq --argjson pc "$plugin_config" '
        .extraKnownMarketplaces = (.extraKnownMarketplaces // {}) * $pc.extraKnownMarketplaces |
        .enabledPlugins = (.enabledPlugins // {}) * $pc.enabledPlugins
      ' 2>/dev/null)
      if [[ -n "$updated" && "$updated" != "null" ]]; then
        echo "$updated" > "$settings_file"
        log_success "Plugin configuration added to settings.json"
      else
        log_error "Failed to update settings.json - manual configuration required"
        return 1
      fi
    fi
  else
    # No existing settings - create new file
    echo "$plugin_config" > "$settings_file"
    log_success "Created settings.json with plugin configuration"
  fi

  log_success "Plugin configured (verify with: claude /plugin list)"
}

# Check GitHub CLI authentication status
check_gh_auth() {
  if ! has_cmd gh; then
    return 1  # gh not installed yet
  fi

  if gh auth status &>/dev/null; then
    GH_AUTHENTICATED=true
    GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "authenticated")
    log_success "GitHub CLI authenticated as: ${GH_USER}"
  else
    GH_AUTHENTICATED=false
    log_warn "GitHub CLI not authenticated"
  fi
}

# Main installation
main() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}     ${BOLD}Claude Autonomous - Issue-Driven Development Installer${NC}     ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Initialize auth status
  GH_AUTHENTICATED=false

  detect_os
  log_info "Detected OS: ${OS} (package manager: ${PKG_MGR})"
  echo ""

  # Check network before downloading anything
  check_connectivity
  echo ""

  # Install dependencies
  if [[ "$SKIP_DEPS" != "true" ]]; then
    echo -e "${BOLD}Installing dependencies...${NC}"
    echo ""

    install_pkg "git" "git" "git" "git" "git" "git"
    install_pkg "curl" "curl" "curl" "curl" "curl" "curl"
    install_pkg "jq" "jq" "jq" "jq" "jq" "jq"

    # xxd (hex dump utility, used by claude-account for newline detection)
    # On Debian/Ubuntu it's standalone, on others it's part of vim
    case "$PKG_MGR" in
      apt) install_pkg "xxd" "xxd" "" "" "" "" ;;
      brew) command -v xxd &>/dev/null || install_pkg "xxd" "" "" "vim" "" "" ;;
      *) command -v xxd &>/dev/null || install_pkg "xxd" "" "vim-common" "" "vim" "vim" ;;
    esac

    # UUID generator
    case "$PKG_MGR" in
      apt) install_pkg "uuidgen" "uuid-runtime" "" "" "" "" || true ;;
      dnf|yum) install_pkg "uuidgen" "" "util-linux" "" "" "" || true ;;
      *) true ;;  # macOS has uuidgen built-in, others have /proc/sys/kernel/random/uuid
    esac

    install_gh
    check_gh_auth  # Check auth status after gh is installed
    install_uv
    install_node
    install_1password_cli
    if [[ "$SKIP_PLAYWRIGHT" != "true" ]]; then
      install_playwright
    else
      log_info "Skipping Playwright installation (SKIP_PLAYWRIGHT=true)"
    fi
    install_claude_code

    echo ""
  else
    log_info "Skipping dependency installation (SKIP_DEPS=true)"
    # Still check gh auth status if gh exists
    check_gh_auth
  fi

  # Install helper scripts
  echo -e "${BOLD}Installing helper scripts...${NC}"
  echo ""
  install_scripts

  # Install plugin
  if [[ "$SKIP_PLUGIN" != "true" ]]; then
    echo ""
    echo -e "${BOLD}Installing Claude Code plugin...${NC}"
    echo ""
    install_plugin
  else
    log_info "Skipping plugin installation (SKIP_PLUGIN=true)"
  fi

  # Summary
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}                   ${BOLD}Installation Complete!${NC}                       ${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo ""

  local step=1

  # Only show gh auth step if not authenticated
  if [[ "$GH_AUTHENTICATED" != "true" ]]; then
    echo "  ${step}. Authenticate GitHub CLI:"
    echo -e "     ${CYAN}gh auth login${NC}"
    echo ""
    step=$((step + 1))
  fi

  echo "  ${step}. Set required environment variables:"
  echo -e "     ${CYAN}export GITHUB_PROJECT=\"https://github.com/users/YOU/projects/N\"${NC}"
  echo -e "     ${CYAN}export GITHUB_PROJECT_NUM=N${NC}"
  echo -e "     ${CYAN}export GH_PROJECT_OWNER=\"@me\"${NC}"
  echo ""
  step=$((step + 1))

  echo "  ${step}. Run autonomous mode from any git repository:"
  echo -e "     ${CYAN}claude-autonomous${NC}"
  echo ""
  step=$((step + 1))

  echo "  ${step}. Or focus on a specific epic:"
  echo -e "     ${CYAN}claude-autonomous --epic 42${NC}"
  echo ""

  echo -e "Verify plugin: ${CYAN}claude /plugin list${NC}"
  echo -e "Documentation: ${BLUE}${REPO_URL}${NC}"
  echo ""
}

main "$@"
