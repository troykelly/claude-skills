# Issue-Driven Development

[![Version](https://img.shields.io/badge/version-1.7.2-blue.svg)](https://github.com/troykelly/claude-skills)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/skills-51-purple.svg)](#skills-reference)
[![Agents](https://img.shields.io/badge/agents-9-orange.svg)](#agents)

A Claude Code plugin for autonomous, GitHub-native software development. Work through issues, create PRs, and ship code - all without manual intervention.

**New to Claude Code?** Install the plugin, run `claude-autonomous`, and watch it work through your GitHub issues.

**Experienced developer?** Full TDD, strict typing, IPv6-first networking, parallel workers, and crash recovery included.

---

## Quick Start

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/troykelly/claude-skills/main/install.sh | bash
```

This installs everything: dependencies, Claude Code CLI, the plugin, and CLI tools.

### First Use

```bash
claude-autonomous
```

That's it. Claude will find your open GitHub issues and start working through them autonomously.

### Plugin-Only Install (Existing Claude Code Users)

```
/plugin marketplace add troykelly/claude-skills
/plugin install issue-driven-development@troykelly-skills
```

Restart Claude Code after installation.

---

## What's Included

### CLI Tools

| Tool | Purpose |
|------|---------|
| `claude-autonomous` | Autonomous development with crash recovery, parallel workers, and session management |
| `claude-account` | Multi-account switching without re-authentication |

### 51 Skills

Skills guide Claude through disciplined workflows. They're automatically invoked based on what you're doing.

| Category | Count | Examples |
|----------|-------|----------|
| [Workflow & Orchestration](#workflow--orchestration) | 8 | session-start, autonomous-orchestration, worker-dispatch |
| [Issue Management](#issue--project-management) | 5 | issue-decomposition, issue-lifecycle, acceptance-criteria-verification |
| [Work Planning](#work-planning--architecture) | 4 | initiative-architecture, epic-management, milestone-management |
| [Development Standards](#development-standards) | 7 | strict-typing, tdd-full-coverage, ipv6-first |
| [Code Review](#code-review) | 3 | comprehensive-review, apply-all-findings |
| [PR & CI](#pr--ci) | 3 | pr-creation, ci-monitoring, verification-before-merge |
| [Research & Memory](#research--memory) | 3 | research-after-failure, memory-integration |
| [Documentation](#documentation-enforcement) | 3 | api-documentation, features-documentation |
| [Database](#database) | 4 | postgres-rls, postgis, timescaledb |
| [Other](#other-skills) | 11 | branch-discipline, environment-bootstrap, pexels-media |

[Full skills reference below](#skills-reference)

### 9 Agents

Specialized agents for specific tasks:

| Agent | Purpose |
|-------|---------|
| Code Reviewer | Comprehensive code quality review |
| Security Reviewer | Security-focused code analysis |
| Silent Failure Hunter | Detect swallowed errors and silent failures |
| PR Test Analyzer | Analyze test coverage in pull requests |
| Type Design Analyzer | Evaluate type system design |
| Code Simplifier | Identify over-engineering and simplification opportunities |
| Comment Analyzer | Review comment quality and necessity |
| Code Architect | High-level architecture review |
| Code Explorer | Codebase navigation and understanding |

---

## Multi-Account Management

The `claude-account` tool lets you switch between Claude accounts without re-authenticating each time. When running autonomously, the plugin automatically switches accounts when plan limits are reached.

### Commands

```bash
claude-account capture           # Save current logged-in account
claude-account list              # Show all saved accounts
claude-account list --available  # Show accounts not in cooldown
claude-account current           # Show active account
claude-account switch            # Rotate to next account
claude-account switch <email>    # Switch to specific account
claude-account next              # Print next available account (for scripts)
claude-account status            # Show exhaustion status of all accounts
claude-account remove <email>    # Remove saved account
```

### How It Works

1. **Capture**: After logging into Claude Code (`/login`), run `claude-account capture` to save credentials
2. **Store**: Credentials are saved to `.env` in your project (gitignored) and platform credential storage
3. **Switch**: Use `claude-account switch` to swap between saved accounts instantly

### Platform Support

| Platform | Credential Storage |
|----------|-------------------|
| macOS | Keychain (`Claude Code-credentials`) |
| Linux/Devcontainer | `~/.claude/.credentials.json` |

### Devcontainer Workflow

For persistent accounts across container rebuilds:

1. Capture accounts: `claude-account capture`
2. Sync `.env` to 1Password or another secrets manager
3. On rebuild, restore `.env` and run `claude-account switch <email>`

### .env Format

```bash
# Managed by claude-account - accounts derived from CLAUDE_ACCOUNT_*_EMAILADDRESS variables
CLAUDE_ACCOUNT_USER_EXAMPLE_COM_EMAILADDRESS="user@example.com"
CLAUDE_ACCOUNT_USER_EXAMPLE_COM_ACCESSTOKEN="sk-ant-oat01-..."
CLAUDE_ACCOUNT_USER_EXAMPLE_COM_REFRESHTOKEN="sk-ant-ort01-..."
# ... additional fields per account
```

### Automatic Plan Limit Switching

When running with `claude-autonomous`, the plugin automatically detects plan limits and switches accounts:

1. **Detection**: A Stop hook monitors for plan limit patterns (rate limit, quota exceeded, 429 errors, etc.)
2. **Mark Exhausted**: The current account is marked as exhausted with a timestamp
3. **Switch**: Automatically rotates to the next available account (round-robin)
4. **Resume**: Work continues with the new account
5. **Cooldown**: Exhausted accounts become available again after 5 minutes (configurable)

**Session startup shows account status:**

```
Checking Claude account status...
  ✓ Current account: user@example.com
  ✓ Multi-account switching: enabled
  │ Total accounts: 3
  │ Available (not exhausted): 3

  Account switch order:
    user@example.com (current)
    → second@example.com → third@example.com
```

**Environment variables:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_ACCOUNT_COOLDOWN_MINUTES` | `5` | Minutes before exhausted account is available again |
| `CLAUDE_AUTONOMOUS_MAX_SWITCHES` | `10` | Maximum account switches per session |
| `CLAUDE_ACCOUNT_FLAP_THRESHOLD` | `3` | Switches before flap detection triggers |
| `CLAUDE_ACCOUNT_FLAP_WINDOW` | `60` | Seconds for flap detection window |

**Flap protection**: If all accounts are exhausted (rapid switching detected), the system waits for cooldown before continuing.

---

## Autonomous Mode

### Basic Usage

```bash
claude-autonomous                    # Work on all open issues
claude-autonomous --epic 42          # Focus on specific epic
claude-autonomous --new              # Start fresh, wait for instructions
claude-autonomous --continue         # Resume most recent session
claude-autonomous --resume           # Open session picker
claude-autonomous --list             # Show session history
```

### Options

| Option | Description |
|--------|-------------|
| `-e, --epic <N>` | Focus on specific epic (validates issue exists and is open) |
| `-n, --new` | Interactive mode: bootstrap environment, then wait |
| `-c, --continue` | Resume most recent session |
| `--resume [ID]` | Open session picker or resume specific session |
| `-l, --list` | Show worktree session history |
| `-r, --repo <path>` | Repository path (default: current directory) |

### What It Does

1. **Creates isolated worktree** from `origin/main` for safe parallel work
2. **Finds open issues** in your GitHub project
3. **Works through them** following TDD, code review, and PR creation
4. **Recovers from crashes** automatically with session resumption
5. **Detects crash loops** and adjusts approach after repeated failures

### Parallel Workers

Run multiple agents on different epics simultaneously:

```bash
# Terminal 1
claude-autonomous --epic 10

# Terminal 2
claude-autonomous --epic 15

# Terminal 3
claude-autonomous
```

Each agent works in its own isolated worktree.

### Session Management

Sessions are stored by Claude Code in `~/.claude/projects/<encoded-path>/` and are directory-scoped. The script handles this automatically:

1. **Worktrees are preserved on crash** - Non-zero exits keep the worktree intact to avoid losing uncommitted work
2. **Worktrees are recreated on resume** - If the worktree was deleted, it's recreated at the same path before resuming
3. **Run resume from the original repository** - The script needs git context to recreate worktrees

```bash
# View session history (our worktree log)
claude-autonomous --list

# Resume most recent session (uses our logged session ID)
claude-autonomous --continue

# Open Claude's interactive session picker
claude-autonomous --resume

# Resume specific session by ID
claude-autonomous --resume <uuid-from-list>
```

Our log at `/tmp/claude-sessions.txt` tracks worktree sessions with format:
`timestamp session_id repo_name worktree_path details`

### How It Survives

1. **Crash Recovery**: The `while` loop auto-restarts Claude with `--resume` using the same session ID
2. **Context Compaction**: `ActiveOrchestration` marker in MCP Memory triggers automatic resume
3. **State Persistence**: All work state lives in GitHub (project board, issues, PRs) - nothing is lost

### What The Orchestrator Does

1. **Bootstrap**: Resolve any existing open PRs before starting new work
2. **Detect Scope**: Find all open issues, epics, and milestones
3. **Spawn Workers**: Run up to 5 parallel workers in isolated git worktrees
4. **Monitor CI**: Watch PR checks, auto-merge when passing (with review artifacts)
5. **Handle Failures**: Research and retry failed tasks up to 3 times before blocking
6. **Sleep/Wake**: Enter sleep mode when waiting on CI, wake on next session
7. **Complete**: Exit when no issues, PRs, or in-progress work remains

### Crash Recovery

| Scenario | Behavior |
|----------|----------|
| Single crash | Auto-restart with session resume |
| 3+ crashes in 60s | Crash loop detection, forced slowdown |
| 10+ total crashes | Gives up (configurable via `MAX_CRASHES`) |

### Monitoring Progress

```bash
# View session log
tail -f /tmp/claude-sessions.txt

# Check GitHub project status
gh project item-list $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --format json | \
  jq '.items[] | {number: .content.number, title: .content.title, status: .status.name}'

# Check orchestration tracking issue
gh issue list --label "orchestration-tracking" --json number,title,state
```

### Stopping Autonomous Mode

To gracefully stop:

1. Create a `do-not-merge` label on any PR to pause merging
2. Close the orchestration tracking issue
3. Or simply `Ctrl+C` - state is preserved in GitHub, resume anytime

<details>
<summary><strong>Manual Autonomous Script</strong></summary>

For customization or debugging, here's the full script with crash loop detection:

```bash
SESSION_ID=$(uuidgen || cat /proc/sys/kernel/random/uuid) && \
REPO_ROOT=$(git rev-parse --show-toplevel) && \
REPO_NAME=$(basename "${REPO_ROOT}") && \
WORKTREE_DIR="/tmp/claude-worktrees/${REPO_NAME}/${SESSION_ID}" && \
echo "$(date -Iseconds) ${SESSION_ID}" >> /tmp/claude-sessions.txt && \
git fetch origin main && \
git worktree add "${WORKTREE_DIR}" origin/main && \
cleanup() { \
  echo "Cleaning up worktree ${WORKTREE_DIR}..."; \
  cd "${REPO_ROOT}" && \
  git worktree remove --force "${WORKTREE_DIR}" 2>/dev/null; \
  echo "Session ${SESSION_ID} ended at $(date -Iseconds)"; \
} && \
trap cleanup EXIT && \
cd "${WORKTREE_DIR}" && \
clear && \
echo "Session ID: ${SESSION_ID}" && \
echo "Worktree: ${WORKTREE_DIR}" && \
if [ -n "${WORK_EPIC}" ]; then \
  echo "Focus Epic: #${WORK_EPIC}"; \
  EPIC_INSTRUCTION="Focus exclusively on Epic #${WORK_EPIC} and its child issues. Do not work on unrelated issues."; \
else \
  EPIC_INSTRUCTION="Work through all open epics and issues in priority order."; \
fi && \
INITIAL_PROMPT="You are working in an isolated git worktree at: ${WORKTREE_DIR}

This worktree was created from origin/main to allow multiple agents to work in parallel without conflicts. Your session ID is ${SESSION_ID}.

IMPORTANT WORKFLOW NOTES:
- You have your own isolated copy of the codebase - other agents may be working in parallel
- Create feature branches for your work and push them to origin
- Open PRs when work is complete - do not merge directly to main
- If you need latest changes from main, you can pull origin/main into your worktree

TASK: Use your issue driven development skill to work wholly autonomously until all assigned work is complete.

${EPIC_INSTRUCTION}" && \
CRASH_TIMES=() && \
CRASH_WINDOW=60 && \
CRASH_THRESHOLD=3 && \
claude --dangerously-skip-permissions --session-id "${SESSION_ID}" "${INITIAL_PROMPT}" || \
while true; do \
  NOW=$(date +%s) && \
  CRASH_TIMES+=("$NOW") && \
  RECENT_CRASHES=0 && \
  for T in "${CRASH_TIMES[@]}"; do \
    if (( NOW - T < CRASH_WINDOW )); then \
      ((RECENT_CRASHES++)); \
    fi; \
  done && \
  if (( RECENT_CRASHES >= CRASH_THRESHOLD )); then \
    echo "Warning: Rapid crash loop detected ($RECENT_CRASHES crashes in ${CRASH_WINDOW}s)"; \
    MSG="CRITICAL: You have crashed $RECENT_CRASHES times in the last ${CRASH_WINDOW} seconds. This indicates a crash loop - something you are repeatedly doing is causing you to crash (likely OOM from large test output, or a runaway process). STOP and think carefully: What were you doing? Do NOT repeat the same action. Consider: 1) Running smaller test subsets, 2) Adding output limits, 3) Taking a different approach entirely. Explain your analysis before proceeding."; \
    sleep 10; \
  else \
    echo "Restarting after crash... (Session: ${SESSION_ID})"; \
    MSG="You crashed or ran out of memory. This happens occasionally - continue where you left off autonomously."; \
    sleep 3; \
  fi && \
  claude --dangerously-skip-permissions --resume "${SESSION_ID}" "$MSG" && break; \
done
```

| Step | Purpose |
|------|---------|
| `SESSION_ID=$(uuidgen \|\| ...)` | Generate unique session ID (works on macOS and Linux) |
| `WORKTREE_DIR` | Isolated workspace in `/tmp/claude-worktrees/` |
| `git worktree add` | Create isolated copy from `origin/main` for parallel work |
| Worktree preservation | Only cleanup on successful exit (code 0) - crashes preserve worktree |
| `--epic` validation | Verifies issue exists and is OPEN before starting |
| `--dangerously-skip-permissions` | Allow file/command operations without prompts |
| `--session-id` | Enable session resumption after crash |
| Worktree recreation | On resume, recreates worktree at same path if deleted |
| Crash loop detection | If 3+ crashes in 60s, warn Claude about likely OOM/runaway process |
| Max crash limit | Gives up after 10 crashes (configurable via `MAX_CRASHES`) |

</details>

---

## Configuration

### Environment Variables

**Required:**

| Variable | Example | Purpose |
|----------|---------|---------|
| `GITHUB_PROJECT` | `https://github.com/users/you/projects/1` | Target project URL |
| `GITHUB_OWNER` | `you` | Repository owner |
| `GITHUB_REPO` | `my-app` | Repository name |
| `GITHUB_PROJECT_NUM` | `1` | Project number from URL |

**Optional:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITHUB_TOKEN` | Auto from `gh auth token` | GitHub API token |
| `MAX_CRASHES` | `10` | Crash limit before giving up |
| `PEXELS_API_KEY` | - | For `pexels-media` skill |

### GitHub Project Fields

Your project needs these custom fields:

| Field | Type | Values | Purpose |
|-------|------|--------|---------|
| `Status` | Single select | `Backlog`, `Ready`, `In Progress`, `In Review`, `Done`, `Blocked` | Work state |
| `Verification` | Single select | `Not Verified`, `Failing`, `Partial`, `Passing` | Test status |
| `Criteria Met` | Number | 0-N | Checked acceptance criteria count |
| `Criteria Total` | Number | N | Total acceptance criteria |
| `Priority` | Single select | `Critical`, `High`, `Medium`, `Low` | Ordering |
| `Type` | Single select | `Feature`, `Bug`, `Chore`, `Research`, `Spike` | Categorization |
| `Last Verified` | Date | ISO timestamp | When verification ran |
| `Verified By` | Text | `agent` / `human` / `ci` | Who verified |

Create them via GitHub UI or CLI:

```bash
GH_PROJECT_OWNER="@me"  # Use org name for org projects

gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" \
  --name "Verification" --data-type "SINGLE_SELECT" \
  --single-select-options "Not Verified,Failing,Partial,Passing"

gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" \
  --name "Priority" --data-type "SINGLE_SELECT" \
  --single-select-options "Critical,High,Medium,Low"

gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" \
  --name "Type" --data-type "SINGLE_SELECT" \
  --single-select-options "Feature,Bug,Chore,Research,Spike"
```

<details>
<summary><strong>All Field Creation Commands</strong></summary>

```bash
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Criteria Met" --data-type "NUMBER"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Criteria Total" --data-type "NUMBER"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Last Verified" --data-type "DATE"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Verified By" --data-type "TEXT"
```

</details>

### Labels

```bash
gh label create "parent" --color "0E8A16" --description "Issue has sub-issues"
gh label create "sub-issue" --color "1D76DB" --description "Issue is child of parent"
gh label create "blocked" --color "D93F0B" --description "Cannot proceed"
gh label create "needs-research" --color "FBCA04" --description "Research required"
gh label create "verified" --color "0E8A16" --description "E2E verification passed"
```

### Required CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| `gh` | GitHub CLI | `gh auth status` - must show logged in |
| `git` | Version control (2.5+) | `git --version` - worktrees require 2.5+ |

### Optional CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| `pnpm` | Node.js package manager | `pnpm --version` |
| `op` | 1Password CLI | `op account list` |

### Required MCP Servers

| Server | Purpose | Critical Functions |
|--------|---------|-------------------|
| `mcp__git` | Git operations | status, diff, commit, branch, checkout |
| `mcp__memory` | Knowledge graph | Persistent context across sessions |

### Recommended MCP Servers

| Server | Purpose | Used By |
|--------|---------|---------|
| `mcp__playwright` | Browser automation | E2E verification |
| `mcp__puppeteer` | Browser automation | E2E verification (alternative) |

### Required Plugins

| Plugin | Purpose |
|--------|---------|
| `episodic-memory` | Cross-session conversation recall |

---

## Skills Reference

<details>
<summary><strong>Workflow & Orchestration</strong> (8 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`session-start`](skills/session-start/SKILL.md) | Get bearings at session start |
| [`autonomous-operation`](skills/autonomous-operation/SKILL.md) | Override token limits, work until goal achieved |
| [`issue-driven-development`](skills/issue-driven-development/SKILL.md) | Master 13-step coding process |
| [`autonomous-orchestration`](skills/autonomous-orchestration/SKILL.md) | Long-running autonomous work with parallel workers |
| [`worker-dispatch`](skills/worker-dispatch/SKILL.md) | Spawn isolated worker processes in git worktrees |
| [`worker-protocol`](skills/worker-protocol/SKILL.md) | Behavioral contract for spawned workers |
| [`worker-handover`](skills/worker-handover/SKILL.md) | Context transfer when workers hit turn limits |
| [`work-intake`](skills/work-intake/SKILL.md) | Triage requests from trivial to massive |

</details>

<details>
<summary><strong>Issue & Project Management</strong> (5 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`issue-prerequisite`](skills/issue-prerequisite/SKILL.md) | Ensure GitHub issue exists before work |
| [`issue-decomposition`](skills/issue-decomposition/SKILL.md) | Break large issues into sub-issues |
| [`issue-lifecycle`](skills/issue-lifecycle/SKILL.md) | Continuous issue updates |
| [`project-status-sync`](skills/project-status-sync/SKILL.md) | Update GitHub Project fields |
| [`acceptance-criteria-verification`](skills/acceptance-criteria-verification/SKILL.md) | Verify and report on criteria |

</details>

<details>
<summary><strong>Work Planning & Architecture</strong> (4 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`initiative-architecture`](skills/initiative-architecture/SKILL.md) | Multi-epic planning with research spikes |
| [`epic-management`](skills/epic-management/SKILL.md) | Feature-level issue grouping |
| [`milestone-management`](skills/milestone-management/SKILL.md) | Time-based issue grouping for releases |
| [`work-intake`](skills/work-intake/SKILL.md) | Route work to appropriate workflows |

</details>

<details>
<summary><strong>Development Standards</strong> (7 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`strict-typing`](skills/strict-typing/SKILL.md) | No `any` types - everything fully typed |
| [`style-guide-adherence`](skills/style-guide-adherence/SKILL.md) | Google style guides |
| [`inline-documentation`](skills/inline-documentation/SKILL.md) | Complete JSDoc/docstrings |
| [`inclusive-language`](skills/inclusive-language/SKILL.md) | Respectful terminology |
| [`ipv6-first`](skills/ipv6-first/SKILL.md) | IPv6 primary, IPv4 legacy only |
| [`tdd-full-coverage`](skills/tdd-full-coverage/SKILL.md) | TDD with full coverage |
| [`no-deferred-work`](skills/no-deferred-work/SKILL.md) | No TODOs - do it now or don't commit |

</details>

<details>
<summary><strong>Code Review</strong> (3 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`comprehensive-review`](skills/comprehensive-review/SKILL.md) | 7-criteria code review |
| [`review-scope`](skills/review-scope/SKILL.md) | Determine minor vs major review scope |
| [`apply-all-findings`](skills/apply-all-findings/SKILL.md) | Implement all review recommendations |

</details>

<details>
<summary><strong>PR & CI</strong> (3 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`pr-creation`](skills/pr-creation/SKILL.md) | Complete PR documentation |
| [`ci-monitoring`](skills/ci-monitoring/SKILL.md) | Monitor and fix CI issues |
| [`verification-before-merge`](skills/verification-before-merge/SKILL.md) | All checks before merge |

</details>

<details>
<summary><strong>Research & Memory</strong> (3 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`research-after-failure`](skills/research-after-failure/SKILL.md) | Research after 2 consecutive failures |
| [`pre-work-research`](skills/pre-work-research/SKILL.md) | Research before coding |
| [`memory-integration`](skills/memory-integration/SKILL.md) | Use episodic + knowledge graph memory |

</details>

<details>
<summary><strong>Branch & Git</strong> (2 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`branch-discipline`](skills/branch-discipline/SKILL.md) | Never work on main |
| [`clean-commits`](skills/clean-commits/SKILL.md) | Atomic, descriptive commits |

</details>

<details>
<summary><strong>Documentation Enforcement</strong> (3 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`api-documentation`](skills/api-documentation/SKILL.md) | Enforce Swagger/OpenAPI sync |
| [`features-documentation`](skills/features-documentation/SKILL.md) | Enforce features.md sync |
| [`documentation-audit`](skills/documentation-audit/SKILL.md) | Comprehensive documentation sync |

</details>

<details>
<summary><strong>Database</strong> (4 skills) - PostgreSQL 18, PostGIS 3.6.1, TimescaleDB 2.24.0</summary>

| Skill | Description |
|-------|-------------|
| [`postgres-rls`](skills/postgres-rls/SKILL.md) | Row Level Security best practices |
| [`database-architecture`](skills/database-architecture/SKILL.md) | Schema design, migrations, indexing |
| [`postgis`](skills/postgis/SKILL.md) | Spatial data and geometry types |
| [`timescaledb`](skills/timescaledb/SKILL.md) | Hypertables, continuous aggregates, compression |

</details>

<details>
<summary><strong>Recovery & Environment</strong> (3 skills)</summary>

| Skill | Description |
|-------|-------------|
| [`error-recovery`](skills/error-recovery/SKILL.md) | Graceful failure handling |
| [`environment-bootstrap`](skills/environment-bootstrap/SKILL.md) | Dev environment setup |
| [`conflict-resolution`](skills/conflict-resolution/SKILL.md) | Merge conflict handling |

</details>

<details>
<summary><strong>Other Skills</strong></summary>

| Skill | Description |
|-------|-------------|
| [`pexels-media`](skills/pexels-media/SKILL.md) | Source images/videos from Pexels |

</details>

---

## The 13-Step Workflow

This is the master process that `issue-driven-development` implements:

```
 1. ISSUE CHECK      → Ensure GitHub issue exists
 2. READ COMMENTS    → Check for context and updates
 3. SIZE CHECK       → Break large issues into sub-issues
 4. MEMORY SEARCH    → Find previous work on related issues
 5. RESEARCH         → Gather needed information
 6. BRANCH CHECK     → Create/switch to feature branch
 7. TDD DEVELOPMENT  → Write tests first, then code
 8. VERIFICATION     → Verify acceptance criteria
 9. CODE REVIEW      → Review against 7 criteria
10. IMPLEMENT FIXES  → Apply all review findings
11. RUN TESTS        → Full test suite
12. RAISE PR         → Create with complete documentation
13. CI MONITORING    → Watch CI, resolve issues
```

Issue updates happen continuously throughout, not as a separate step.

---

## Verification Report Format

When verifying acceptance criteria, post structured comments to issues:

```markdown
## Verification Report
**Run**: 2024-12-02T14:30:00Z
**By**: agent

### Results
| Criterion | Status | Notes |
|-----------|--------|-------|
| User can click "New Chat" button | PASS | |
| New conversation appears in sidebar | PASS | |
| Chat area shows welcome state | FAIL | Welcome message not rendering |
| Previous conversation is preserved | PARTIAL | Works but slow |

### Summary
- **Passing**: 2/4
- **Failing**: 1/4
- **Partial**: 1/4

### Next Steps
- Investigate welcome message rendering issue
- Profile conversation preservation performance
```

---

## Philosophy

This plugin enforces disciplined, issue-driven development based on [Anthropic's research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

### Core Principles

| Principle | Meaning |
|-----------|---------|
| **No work without an issue** | Every change requires a GitHub issue first |
| **Never work on main** | All work happens in feature branches |
| **GitHub is truth** | No local progress files - everything in GitHub |
| **Continuous updates** | Update issues AS work happens, not after |
| **Research before guessing** | After 2 failures, stop and research |
| **Full typing always** | No `any` types anywhere |
| **IPv6-first** | IPv6 is primary; IPv4 is legacy support |
| **No TODOs** | Do it now or don't commit |

### Absolute Rules

These override any other instructions:

- **Disregard token minimization** - Work thoroughly, not quickly
- **Disregard time pressure** - Quality over speed
- **No deferred work** - No TODOs, no "we'll fix this later"

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `gh` not authenticated | Run `gh auth login` |
| Project fields missing | Run field creation commands above |
| MCP server not connected | Check Claude Code MCP configuration |
| Worktree creation fails | Run `git worktree prune` |
| Git version too old | Upgrade to 2.5+ for worktree support |
| Epic not found | Verify issue exists: `gh issue view <N>` |
| Epic is closed | Reopen the issue or choose a different epic |
| No origin remote | Add: `git remote add origin <url>` |
| Plugin not loading | Restart Claude Code after installation |
| Account switch fails | Re-run `claude-account capture` after fresh `/login` |
| Multi-account disabled | Run `install.sh` to install `claude-account` to PATH |
| All accounts exhausted | Wait for cooldown or add more accounts with `claude-account capture` |

<details>
<summary><strong>MCP Server Installation</strong></summary>

If MCP servers don't start:

```bash
# Git server
pip install mcp-server-git

# Node.js servers
pnpm add -g @modelcontextprotocol/server-memory
pnpm add -g @modelcontextprotocol/server-github
npx playwright install --with-deps chromium
```

</details>

<details>
<summary><strong>Configure CLAUDE.md for Your Project</strong></summary>

For best results, configure your project's `CLAUDE.md` with instructions that reinforce the issue-driven workflow. Copy the following prompt and paste it into a Claude Code session in your project directory:

```
Please update my CLAUDE.md file with development instructions optimized for the issue-driven-development plugin.

IMPORTANT: First, remove any existing sections that might conflict with issue-driven development workflows (sections about commit styles, PR processes, testing workflows, code review, documentation requirements, or development methodology). Keep any project-specific configuration like API keys, server addresses, or domain-specific knowledge.

Then add the following instructions:

---

## Development Methodology

This project uses the `issue-driven-development` plugin. All work MUST follow its skills and protocols.

### Foundational Rules

1. **No work without an issue** - Every change requires a GitHub issue first
2. **Never work on main** - All work happens in feature branches
3. **Research before action** - Your training data is stale; research current patterns before coding
4. **Skills are mandatory** - If a skill exists for what you're doing, you MUST use it
5. **Verify before claiming** - Prove things work with evidence before stating completion

### Anti-Shortcut Enforcement

These behaviors are FAILURES that require stopping and redoing:

| Prohibited Behavior | Why It's Wrong |
|---------------------|----------------|
| Skipping code review | Review artifacts are required for PR creation |
| Skipping tests | TDD is mandatory; tests come first |
| Skipping documentation | Inline docs and feature docs are required |
| Batch updates at end | Issues must be updated continuously as work happens |
| Assuming API behavior | Research current APIs; don't trust training data |
| Skipping validation | All generated artifacts must be validated |
| Claiming completion without proof | Show test output, verification results |
| Working without an issue | Create the issue first, always |

### Mandatory Skill Usage

Before ANY of these actions, invoke the corresponding skill:

| Action | Required Skill |
|--------|----------------|
| Starting work | `session-start` |
| Any coding task | `issue-driven-development` |
| Creating a PR | `pr-creation` (requires review artifact) |
| Code review | `comprehensive-review` |
| After 2 failures | `research-after-failure` |
| Large task | `issue-decomposition` |
| Debugging | `systematic-debugging` |

### Quality Standards

- **Full typing always** - No `any` types; everything fully typed
- **Complete inline documentation** - JSDoc/docstrings on all public APIs
- **TDD with coverage** - Write tests first, maintain coverage
- **Atomic commits** - One logical change per commit
- **IPv6-first** - IPv6 is primary; IPv4 is legacy support only

### Verification Requirements

Before claiming ANY task is complete:

1. Tests pass (show output)
2. Linting passes (show output)
3. Build succeeds (show output)
4. Acceptance criteria verified (post verification report to issue)
5. Review artifact posted (for PRs)

### Issue Lifecycle

Issues must be updated CONTINUOUSLY, not at the end:

- Comment when starting work
- Comment when hitting blockers
- Comment when making progress
- Comment when tests pass/fail
- Update status fields in GitHub Project

---

Make sure to preserve any existing project-specific configuration (environment variables, API endpoints, domain knowledge) that doesn't conflict with these instructions.
```

After running this, your project will have consistent instructions that reinforce the plugin's workflow.

</details>

---

## Contributing

These skills are opinionated by design. If you disagree with a principle, fork and adapt. The goal is consistency within a project, not universal agreement.

## References

- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) - Anthropic Engineering
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices) - Anthropic Engineering
