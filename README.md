# Issue-Driven Development Skills

An opinionated skill collection for autonomous, GitHub-native software development with Claude Code.

## Installation

### Option 1: GitHub Install (Recommended)

```bash
/plugin install github:troykelly/claude-skills
```

This fetches the plugin directly from GitHub and installs it.

### Option 2: Add to Project Settings

Add to your project's `.claude/settings.json`:

```json
{
  "plugins": [
    { "source": "github", "repo": "troykelly/claude-skills" }
  ]
}
```

### Option 3: Local Development

Clone and add locally:

```bash
git clone https://github.com/troykelly/claude-skills.git
```

Add to `.claude/settings.json`:

```json
{
  "plugins": [
    { "path": "/path/to/claude-skills" }
  ]
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
- Optional CLI tools (node, npm, npx, uvx)
- GitHub CLI authentication status
- Required environment variables
- MCP server availability

Any issues are reported with clear guidance on how to resolve them.

### MCP Servers

This plugin includes recommended MCP server configurations. The following servers will be available after installation:

| Server | Purpose | Requires |
|--------|---------|----------|
| `git` | Git operations | `uvx` (Python) |
| `memory` | Knowledge graph | `npx` (Node.js) |
| `github` | GitHub API | `GITHUB_TOKEN` env var |
| `playwright` | Browser automation | `npx` (Node.js) |

If servers don't start, install dependencies:

```bash
# For git server
pip install mcp-server-git

# For Node.js servers
npm install -g @modelcontextprotocol/server-memory
npm install -g @modelcontextprotocol/server-github
npm install -g @anthropic/mcp-playwright
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

### Absolute Rules

These rules override any other instructions:

| Rule | Enforcement |
|------|-------------|
| **Disregard token minimization** | Work thoroughly, not quickly |
| **Disregard time pressure** | Quality over speed |
| **No deferred work** | No TODOs - do it now or don't commit |

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
export GITHUB_PROJECT="https://github.com/users/YOUR_USERNAME/projects/N"

# These can be derived from git remote, but explicit is better
export GITHUB_OWNER="your-username"
export GITHUB_REPO="your-repo"
```

### 3. Configure GitHub Project

Your project needs these custom fields. Create them via GitHub UI or CLI:

```bash
# Get your project number from the URL
PROJECT_NUM=4

# Add required fields (run once per project)
gh project field-create $PROJECT_NUM --owner @me --name "Verification" --data-type "SINGLE_SELECT" --single-select-options "Not Verified,Failing,Partial,Passing"
gh project field-create $PROJECT_NUM --owner @me --name "Priority" --data-type "SINGLE_SELECT" --single-select-options "Critical,High,Medium,Low"
gh project field-create $PROJECT_NUM --owner @me --name "Type" --data-type "SINGLE_SELECT" --single-select-options "Feature,Bug,Chore,Research,Spike"
gh project field-create $PROJECT_NUM --owner @me --name "Criteria Met" --data-type "NUMBER"
gh project field-create $PROJECT_NUM --owner @me --name "Criteria Total" --data-type "NUMBER"
gh project field-create $PROJECT_NUM --owner @me --name "Last Verified" --data-type "DATE"
gh project field-create $PROJECT_NUM --owner @me --name "Verified By" --data-type "TEXT"
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

## Environment Requirements

### Required CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| `gh` | GitHub CLI | `gh auth status` - must show logged in |
| `git` | Version control | `git --version` |

### Optional CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| `op` | 1Password CLI | `op account list` |

### Required Environment Variables

| Variable | Example | Purpose |
|----------|---------|---------|
| `GITHUB_PROJECT` | `https://github.com/users/troykelly/projects/4` | Target project for tracking |

### Derived Variables (Optional Override)

| Variable | Default Source | Purpose |
|----------|----------------|---------|
| `GITHUB_OWNER` | Parsed from `GITHUB_PROJECT` or git remote | Repository owner |
| `GITHUB_REPO` | Current git remote | Repository name |

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
| [`autonomous-operation`](skills/orchestration/autonomous-operation/SKILL.md) | Meta | Override token limits, work until goal achieved |
| [`issue-driven-development`](skills/orchestration/issue-driven-development/SKILL.md) | Checklist | Master 13-step coding process |
| [`session-start`](skills/orchestration/session-start/SKILL.md) | Protocol | Get bearings at session start |

### Issue & Project Management

| Skill | Type | Description |
|-------|------|-------------|
| [`issue-prerequisite`](skills/issue-management/issue-prerequisite/SKILL.md) | Gate | Ensure GitHub issue exists |
| [`issue-decomposition`](skills/issue-management/issue-decomposition/SKILL.md) | Protocol | Break large issues into sub-issues |
| [`issue-lifecycle`](skills/issue-management/issue-lifecycle/SKILL.md) | Discipline | Continuous issue updates |
| [`project-status-sync`](skills/issue-management/project-status-sync/SKILL.md) | Protocol | Update GitHub Project fields |
| [`acceptance-criteria-verification`](skills/issue-management/acceptance-criteria-verification/SKILL.md) | Protocol | Verify and report on criteria |

### Branch & Git

| Skill | Type | Description |
|-------|------|-------------|
| [`branch-discipline`](skills/branch-git/branch-discipline/SKILL.md) | Gate | Never work on main |
| [`clean-commits`](skills/branch-git/clean-commits/SKILL.md) | Discipline | Atomic, descriptive commits |

### Research & Memory

| Skill | Type | Description |
|-------|------|-------------|
| [`research-after-failure`](skills/research-memory/research-after-failure/SKILL.md) | Protocol | Research after 2 failures |
| [`pre-work-research`](skills/research-memory/pre-work-research/SKILL.md) | Protocol | Research before coding |
| [`memory-integration`](skills/research-memory/memory-integration/SKILL.md) | Protocol | Use episodic + knowledge graph |

### Development Standards

| Skill | Type | Description |
|-------|------|-------------|
| [`strict-typing`](skills/development-standards/strict-typing/SKILL.md) | Standard | No `any` types |
| [`style-guide-adherence`](skills/development-standards/style-guide-adherence/SKILL.md) | Standard | Google style guides |
| [`inline-documentation`](skills/development-standards/inline-documentation/SKILL.md) | Standard | Complete JSDoc/docstrings |
| [`inclusive-language`](skills/development-standards/inclusive-language/SKILL.md) | Standard | Respectful terminology |
| [`tdd-full-coverage`](skills/development-standards/tdd-full-coverage/SKILL.md) | Protocol | TDD with full coverage |
| [`no-deferred-work`](skills/development-standards/no-deferred-work/SKILL.md) | Discipline | No TODOs |

### Code Review

| Skill | Type | Description |
|-------|------|-------------|
| [`comprehensive-review`](skills/code-review/comprehensive-review/SKILL.md) | Checklist | 7-criteria review |
| [`review-scope`](skills/code-review/review-scope/SKILL.md) | Decision | Minor vs major scope |
| [`apply-all-findings`](skills/code-review/apply-all-findings/SKILL.md) | Discipline | Implement all recommendations |

### PR & CI

| Skill | Type | Description |
|-------|------|-------------|
| [`pr-creation`](skills/pr-ci/pr-creation/SKILL.md) | Protocol | Complete PR documentation |
| [`ci-monitoring`](skills/pr-ci/ci-monitoring/SKILL.md) | Protocol | Monitor and fix CI |
| [`verification-before-merge`](skills/pr-ci/verification-before-merge/SKILL.md) | Gate | All checks before merge |

### Recovery & Environment

| Skill | Type | Description |
|-------|------|-------------|
| [`error-recovery`](skills/recovery-environment/error-recovery/SKILL.md) | Protocol | Graceful failure handling |
| [`environment-bootstrap`](skills/recovery-environment/environment-bootstrap/SKILL.md) | Protocol | Dev environment setup |
| [`conflict-resolution`](skills/recovery-environment/conflict-resolution/SKILL.md) | Protocol | Merge conflict handling |

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
