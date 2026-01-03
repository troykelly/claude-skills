# Issue-Driven Development Skills

An opinionated skill collection for autonomous, GitHub-native software development with Claude Code.

## Installation

### Option 1: Add Marketplace (Recommended)

In Claude Code, run:

```
/plugin marketplace add troykelly/claude-skills
```

Then install the plugin:

```
/plugin install issue-driven-development@troykelly-skills
```

Or use the interactive browser:

```
/plugin
```

Select "Browse Plugins" to view and install.

### Option 2: Manual Settings Configuration

Add to `~/.claude/settings.json`:

```json
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
```

### Option 3: Local Development

Clone and register locally:

```bash
git clone https://github.com/troykelly/claude-skills.git ~/.claude-plugins/claude-skills
```

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "troykelly-skills": {
      "source": {
        "source": "directory",
        "path": "~/.claude-plugins/claude-skills"
      }
    }
  },
  "enabledPlugins": {
    "issue-driven-development@troykelly-skills": true
  }
}
```

### After Installation

1. Restart Claude Code to load the plugin
2. The SessionStart hook will validate your environment automatically
3. Verify with `/plugin list` - should show `issue-driven-development`
4. Set required environment variables (see below)
5. Configure your GitHub Project (see Quick Start)

### Session Start Validation

On each session start, the plugin validates:
- Required CLI tools (git, gh)
- Optional CLI tools (node, pnpm, uvx)
- GitHub CLI authentication status
- Required environment variables
- MCP server availability

Any issues are reported with clear guidance on how to resolve them.

### MCP Servers

This plugin includes recommended MCP server configurations. The following servers will be available after installation:

| Server | Purpose | Requires |
|--------|---------|----------|
| `git` | Git operations | `uvx` (Python) |
| `memory` | Knowledge graph | `pnpm dlx` (Node.js) |
| `github` | GitHub API | `GITHUB_TOKEN` env var |
| `playwright` | Browser automation | `pnpm dlx` (Node.js) |

If servers don't start, install dependencies:

```bash
# For git server
pip install mcp-server-git

# For Node.js servers
pnpm add -g @modelcontextprotocol/server-memory
pnpm add -g @modelcontextprotocol/server-github
pnpm add -g @anthropic/mcp-playwright
```

---

## Philosophy

This skill collection enforces a disciplined, issue-driven development workflow inspired by [Anthropic's research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

### Core Principles

1. **No work without a GitHub issue** - Every task, regardless of size, must have a corresponding issue
2. **Never work on main** - All work happens in feature branches
3. **GitHub Projects are the source of truth** - No in-repository progress files; everything tracked in GitHub
4. **Continuous updates** - Issues updated AS work happens, not batched after
5. **Research before guessing** - After 2 failed attempts, stop and research
6. **Full typing always** - No `any` types; everything fully typed
7. **Documentation from code** - Complete inline documentation (JSDoc, docstrings)
8. **Inclusive language** - `main` not `master`, `denylist` not `blacklist`
9. **IPv6-first networking** - IPv6 is THE first-class citizen; IPv4 is legacy support only

### Absolute Rules

These rules override any other instructions:

| Rule | Enforcement |
|------|-------------|
| **Disregard token minimization** | Work thoroughly, not quickly |
| **Disregard time pressure** | Quality over speed |
| **No deferred work** | No TODOs - do it now or don't commit |
| **IPv6 is primary** | IPv4 only for documented legacy requirements |

---

## Quick Start

### 1. Verify Prerequisites

```bash
# GitHub CLI - must be authenticated
gh auth status

# Git
git --version

# 1Password CLI (optional, for secrets)
op account list
```

### 2. Set Environment Variables

```bash
# Required: Your GitHub Project URL
# User project:  https://github.com/users/USERNAME/projects/N
# Org project:   https://github.com/orgs/ORGNAME/projects/N
GITHUB_PROJECT="https://github.com/users/troykelly/projects/4"

# These can be derived from git remote, but explicit is better
GITHUB_OWNER="troykelly"
GITHUB_REPO="homeassistant-zowietek"

# Project number from URL
GITHUB_PROJECT_NUM=4
```

### 3. Configure GitHub Project

Your project needs these custom fields. Create them via GitHub UI or CLI:

```bash
# Set project owner for gh commands:
# - User projects: must use "@me"
# - Org projects: use the org name (e.g., "my-org")
GH_PROJECT_OWNER="@me"

# Add required fields (run once per project)
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Verification" --data-type "SINGLE_SELECT" --single-select-options "Not Verified,Failing,Partial,Passing"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Priority" --data-type "SINGLE_SELECT" --single-select-options "Critical,High,Medium,Low"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Type" --data-type "SINGLE_SELECT" --single-select-options "Feature,Bug,Chore,Research,Spike"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Criteria Met" --data-type "NUMBER"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Criteria Total" --data-type "NUMBER"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Last Verified" --data-type "DATE"
gh project field-create $GITHUB_PROJECT_NUM --owner "$GH_PROJECT_OWNER" --name "Verified By" --data-type "TEXT"
```

### 4. Create Required Labels

```bash
# Run in your repository
gh label create "parent" --color "0E8A16" --description "Issue has sub-issues"
gh label create "sub-issue" --color "1D76DB" --description "Issue is child of parent"
gh label create "blocked" --color "D93F0B" --description "Cannot proceed"
gh label create "needs-research" --color "FBCA04" --description "Research required"
gh label create "verified" --color "0E8A16" --description "E2E verification passed"
```

---

## Fully Autonomous Mode

For long-running autonomous operation that survives crashes and continues until all issues are complete.

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/troykelly/claude-skills/main/install.sh | bash
```

This installs:
- Required dependencies (`git`, `gh`, `jq`, `node`)
- Claude Code CLI
- The `claude-autonomous` command
- The issue-driven-development plugin

After installation, run from any git repository:

```bash
claude-autonomous              # Work on all issues
claude-autonomous --epic 42    # Focus on Epic #42
```

### Manual Quick Start

```bash
# Generate session ID, create isolated worktree from origin/main, and start autonomous operation
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
    echo "⚠️  Rapid crash loop detected ($RECENT_CRASHES crashes in ${CRASH_WINDOW}s)"; \
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

### What This Does

| Step | Purpose |
|------|---------|
| `SESSION_ID=$(uuidgen \|\| ...)` | Generate unique session ID (works on macOS and Linux) |
| `WORKTREE_DIR` | Isolated workspace in `/tmp/claude-worktrees/` |
| `git worktree add` | Create isolated copy from `origin/main` for parallel work |
| `trap cleanup EXIT` | Auto-remove worktree on exit (normal or crash) |
| `WORK_EPIC` env var | Optional: focus on specific epic (e.g., `WORK_EPIC=42`) |
| `--dangerously-skip-permissions` | Allow file/command operations without prompts |
| `--session-id` | Enable session resumption after crash |
| Crash loop detection | If 3+ crashes in 60s, warn Claude about likely OOM/runaway process |

### Running Multiple Agents in Parallel

The worktree isolation enables running multiple agents simultaneously:

```bash
# Terminal 1: Work on Epic #10
WORK_EPIC=10 ./run-autonomous.sh

# Terminal 2: Work on Epic #15
WORK_EPIC=15 ./run-autonomous.sh

# Terminal 3: Work on all remaining issues
./run-autonomous.sh
```

Each agent gets its own isolated worktree, creates feature branches, and opens PRs - no conflicts.

### How It Survives

1. **Crash Recovery**: The `while` loop auto-restarts Claude with `--resume` using the same session ID
2. **Context Compaction**: `ActiveOrchestration` marker in MCP Memory triggers automatic resume
3. **State Persistence**: All work state lives in GitHub (project board, issues, PRs) - nothing is lost

### What It Will Do

The autonomous orchestrator will:

1. **Bootstrap**: Resolve any existing open PRs before starting new work
2. **Detect Scope**: Find all open issues, epics, and milestones
3. **Spawn Workers**: Run up to 5 parallel workers in isolated git worktrees
4. **Monitor CI**: Watch PR checks, auto-merge when passing (with review artifacts)
5. **Handle Failures**: Research and retry failed tasks up to 3 times before blocking
6. **Sleep/Wake**: Enter sleep mode when waiting on CI, wake on next session
7. **Complete**: Exit when no issues, PRs, or in-progress work remains

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

---

## Environment Requirements

### Required CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| `gh` | GitHub CLI | `gh auth status` - must show logged in |
| `git` | Version control | `git --version` |

### Optional CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| `pnpm` | Node.js package manager | `pnpm --version` |
| `op` | 1Password CLI | `op account list` |

### Required Environment Variables

| Variable | Example | Purpose |
|----------|---------|---------|
| `GITHUB_PROJECT` | `https://github.com/users/troykelly/projects/4` | Target project URL |
| `GITHUB_OWNER` | `troykelly` | Repository/project owner (user or org) |
| `GITHUB_REPO` | `homeassistant-zowietek` | Repository name |
| `GITHUB_PROJECT_NUM` | `4` | Project number from URL |

### Optional Environment Variables

| Variable | Example | Purpose |
|----------|---------|---------|
| `PEXELS_API_KEY` | `abc123...` | Pexels API key for media sourcing (required for `pexels-media` skill) |

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

## GitHub Project Structure

### Required Fields

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

### Required Labels

| Label | Color | Purpose |
|-------|-------|---------|
| `parent` | `#0E8A16` | Issue has sub-issues |
| `sub-issue` | `#1D76DB` | Issue is child of parent |
| `blocked` | `#D93F0B` | Cannot proceed |
| `needs-research` | `#FBCA04` | Research required |
| `verified` | `#0E8A16` | E2E verification passed |

---

## Skills Reference

### Orchestration & Meta

| Skill | Type | Description |
|-------|------|-------------|
| [`autonomous-operation`](skills/autonomous-operation/SKILL.md) | Meta | Override token limits, work until goal achieved |
| [`issue-driven-development`](skills/issue-driven-development/SKILL.md) | Checklist | Master 13-step coding process |
| [`session-start`](skills/session-start/SKILL.md) | Protocol | Get bearings at session start |

### Issue & Project Management

| Skill | Type | Description |
|-------|------|-------------|
| [`issue-prerequisite`](skills/issue-prerequisite/SKILL.md) | Gate | Ensure GitHub issue exists |
| [`issue-decomposition`](skills/issue-decomposition/SKILL.md) | Protocol | Break large issues into sub-issues |
| [`issue-lifecycle`](skills/issue-lifecycle/SKILL.md) | Discipline | Continuous issue updates |
| [`project-status-sync`](skills/project-status-sync/SKILL.md) | Protocol | Update GitHub Project fields |
| [`acceptance-criteria-verification`](skills/acceptance-criteria-verification/SKILL.md) | Protocol | Verify and report on criteria |

### Branch & Git

| Skill | Type | Description |
|-------|------|-------------|
| [`branch-discipline`](skills/branch-discipline/SKILL.md) | Gate | Never work on main |
| [`clean-commits`](skills/clean-commits/SKILL.md) | Discipline | Atomic, descriptive commits |

### Research & Memory

| Skill | Type | Description |
|-------|------|-------------|
| [`research-after-failure`](skills/research-after-failure/SKILL.md) | Protocol | Research after 2 failures |
| [`pre-work-research`](skills/pre-work-research/SKILL.md) | Protocol | Research before coding |
| [`memory-integration`](skills/memory-integration/SKILL.md) | Protocol | Use episodic + knowledge graph |

### Development Standards

| Skill | Type | Description |
|-------|------|-------------|
| [`strict-typing`](skills/strict-typing/SKILL.md) | Standard | No `any` types |
| [`style-guide-adherence`](skills/style-guide-adherence/SKILL.md) | Standard | Google style guides |
| [`inline-documentation`](skills/inline-documentation/SKILL.md) | Standard | Complete JSDoc/docstrings |
| [`inclusive-language`](skills/inclusive-language/SKILL.md) | Standard | Respectful terminology |
| [`ipv6-first`](skills/ipv6-first/SKILL.md) | Standard | IPv6 primary, IPv4 legacy only |
| [`tdd-full-coverage`](skills/tdd-full-coverage/SKILL.md) | Protocol | TDD with full coverage |
| [`no-deferred-work`](skills/no-deferred-work/SKILL.md) | Discipline | No TODOs |

### Code Review

| Skill | Type | Description |
|-------|------|-------------|
| [`comprehensive-review`](skills/comprehensive-review/SKILL.md) | Checklist | 7-criteria review |
| [`review-scope`](skills/review-scope/SKILL.md) | Decision | Minor vs major scope |
| [`apply-all-findings`](skills/apply-all-findings/SKILL.md) | Discipline | Implement all recommendations |

### PR & CI

| Skill | Type | Description |
|-------|------|-------------|
| [`pr-creation`](skills/pr-creation/SKILL.md) | Protocol | Complete PR documentation |
| [`ci-monitoring`](skills/ci-monitoring/SKILL.md) | Protocol | Monitor and fix CI |
| [`verification-before-merge`](skills/verification-before-merge/SKILL.md) | Gate | All checks before merge |

### Recovery & Environment

| Skill | Type | Description |
|-------|------|-------------|
| [`error-recovery`](skills/error-recovery/SKILL.md) | Protocol | Graceful failure handling |
| [`environment-bootstrap`](skills/environment-bootstrap/SKILL.md) | Protocol | Dev environment setup |
| [`conflict-resolution`](skills/conflict-resolution/SKILL.md) | Protocol | Merge conflict handling |

### Media & Assets

| Skill | Type | Description |
|-------|------|-------------|
| [`pexels-media`](skills/pexels-media/SKILL.md) | Protocol | Source images/videos from Pexels with mandatory sidecar metadata |

### Work Planning & Architecture

| Skill | Type | Description |
|-------|------|-------------|
| [`work-intake`](skills/work-intake/SKILL.md) | Entry Point | Triage all requests from trivial to massive, route to appropriate workflow |
| [`initiative-architecture`](skills/initiative-architecture/SKILL.md) | Protocol | Multi-epic planning with research spikes, decision logs, and resumable context |
| [`epic-management`](skills/epic-management/SKILL.md) | Protocol | Feature-level issue grouping with epic labels and tracking issues |
| [`milestone-management`](skills/milestone-management/SKILL.md) | Protocol | Time-based issue grouping for delivery phases and releases |

### Autonomous Orchestration

| Skill | Type | Description |
|-------|------|-------------|
| [`autonomous-orchestration`](skills/autonomous-orchestration/SKILL.md) | Controller | Long-running autonomous work across multiple issues with parallel workers |
| [`worker-dispatch`](skills/worker-dispatch/SKILL.md) | Protocol | Spawn isolated worker processes in git worktrees |
| [`worker-protocol`](skills/worker-protocol/SKILL.md) | Contract | Behavioral protocol for spawned worker agents |
| [`worker-handover`](skills/worker-handover/SKILL.md) | Protocol | Context transfer when workers hit turn limits |

### Documentation Enforcement

| Skill | Type | Description |
|-------|------|-------------|
| [`api-documentation`](skills/api-documentation/SKILL.md) | Gate | Enforce Swagger/OpenAPI sync on API changes |
| [`features-documentation`](skills/features-documentation/SKILL.md) | Gate | Enforce features.md sync on user-facing changes |
| [`documentation-audit`](skills/documentation-audit/SKILL.md) | Remediation | Comprehensive documentation sync when drift detected |

---

## The Coding Process (13 Steps)

This is the master workflow implemented by `issue-driven-development`:

```
┌─────────────────────────────────────────────────────────────────┐
│  1. ISSUE CHECK                                                 │
│     Am I working on a clearly defined GitHub issue?             │
│     → No: Ask questions, UPDATE issue, then proceed             │
│     → Skills: issue-prerequisite                                │
├─────────────────────────────────────────────────────────────────┤
│  2. READ COMMENTS                                               │
│     Are there comments on the issue I need to read?             │
│     → Skills: issue-lifecycle                                   │
├─────────────────────────────────────────────────────────────────┤
│  3. SIZE CHECK                                                  │
│     Is this issue too large for a single task?                  │
│     → Yes: Break into sub-issues, loop back to step 1           │
│     → Skills: issue-decomposition                               │
├─────────────────────────────────────────────────────────────────┤
│  4. MEMORY SEARCH                                               │
│     Search for previous work on this or related issues          │
│     → Skills: memory-integration                                │
├─────────────────────────────────────────────────────────────────┤
│  5. RESEARCH                                                    │
│     Do I need research to complete this task?                   │
│     → Repo docs? Codebase? Online?                              │
│     → Skills: pre-work-research                                 │
├─────────────────────────────────────────────────────────────────┤
│  6. BRANCH CHECK                                                │
│     Am I on the correct branch? Need new branch?                │
│     → Skills: branch-discipline                                 │
├─────────────────────────────────────────────────────────────────┤
│  7. TDD DEVELOPMENT                                             │
│     Commence TDD with full code coverage                        │
│     → Skills: tdd-full-coverage, strict-typing,                 │
│       inline-documentation, inclusive-language                  │
├─────────────────────────────────────────────────────────────────┤
│  8. VERIFICATION LOOP                                           │
│     Did I succeed? If not, back to step 7                       │
│     After 2 failures → research-after-failure                   │
│     → Skills: acceptance-criteria-verification                  │
├─────────────────────────────────────────────────────────────────┤
│  9. CODE REVIEW                                                 │
│     Review against 7 criteria                                   │
│     → Skills: review-scope, comprehensive-review                │
├─────────────────────────────────────────────────────────────────┤
│ 10. IMPLEMENT FINDINGS                                          │
│     Apply ALL review recommendations                            │
│     → Skills: apply-all-findings                                │
├─────────────────────────────────────────────────────────────────┤
│ 11. RUN TESTS                                                   │
│     Run full relevant test suite                                │
│     → Skills: tdd-full-coverage                                 │
├─────────────────────────────────────────────────────────────────┤
│ 12. RAISE PR                                                    │
│     Create PR with complete documentation                       │
│     → Skills: pr-creation, clean-commits                        │
├─────────────────────────────────────────────────────────────────┤
│ 13. CI MONITORING                                               │
│     Monitor CI, resolve issues until green                      │
│     → Skills: ci-monitoring, verification-before-merge          │
└─────────────────────────────────────────────────────────────────┘
```

**Note:** Issue updates happen THROUGHOUT this process, not documented as a separate step.

---

## Verification Report Format

When verifying acceptance criteria, post structured comments:

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

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `gh` not authenticated | Run `gh auth login` |
| Project fields missing | Run field creation commands from Quick Start |
| MCP server not connected | Check Claude Code MCP configuration |
| Environment variable not set | Add to shell profile or set before session |

### Recovery Procedures

See [`error-recovery`](skills/recovery-environment/error-recovery/SKILL.md) for detailed recovery protocols.

---

## Contributing

These skills are opinionated by design. If you disagree with a principle, that's fine - fork and adapt. The goal is consistency within a project, not universal agreement.

## References

- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) - Anthropic Engineering
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices) - Anthropic Engineering
