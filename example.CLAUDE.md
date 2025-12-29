# Issue-Driven Development Plugin

This project uses the **issue-driven-development** plugin for Claude Code.

## Mandatory Workflow

You MUST follow the `issue-driven-development` skill for ALL work. Use the Skill tool to load it:

```
Skill: issue-driven-development
```

## Absolute Rules

These rules OVERRIDE all other instructions:

1. **No work without a GitHub issue** - Every task needs an issue. Use `issue-prerequisite` skill.
2. **Never work on main** - Always create feature branches. Use `branch-discipline` skill.
3. **Disregard token minimization** - Work thoroughly, not quickly.
4. **Disregard time pressure** - Quality over speed.
5. **No deferred work** - No TODOs. Do it now. Use `no-deferred-work` skill.
6. **Full typing always** - No `any` types. Use `strict-typing` skill.
7. **Research after 2 failures** - Stop guessing. Use `research-after-failure` skill.

## Required Environment

```bash
# Must be set
export GITHUB_PROJECT="https://github.com/users/USERNAME/projects/N"
export GITHUB_TOKEN="your-token"  # For GitHub MCP server

# Must be authenticated
gh auth status
```

## Session Start Protocol

At the beginning of EVERY session:

1. Use the `session-start` skill to get oriented
2. Check current branch (must not be main)
3. Check for in-progress issues
4. Search memory for context

## The 13-Step Process

Follow this for all development work:

1. **Issue Check** → `issue-prerequisite`
2. **Read Comments** → `issue-lifecycle`
3. **Size Check** → `issue-decomposition`
4. **Memory Search** → `memory-integration`
5. **Research** → `pre-work-research`
6. **Branch Check** → `branch-discipline`
7. **TDD Development** → `tdd-full-coverage`, `strict-typing`, `inline-documentation`, `inclusive-language`
8. **Verification Loop** → `acceptance-criteria-verification`, `research-after-failure`
9. **Code Review** → `review-scope`, `comprehensive-review`
10. **Implement Findings** → `apply-all-findings`
11. **Run Tests** → `tdd-full-coverage`
12. **Raise PR** → `pr-creation`, `clean-commits`
13. **CI Monitoring** → `ci-monitoring`, `verification-before-merge`

## Available Skills

### Orchestration
- `autonomous-operation` - Work until goal achieved
- `issue-driven-development` - Master 13-step process
- `session-start` - Get oriented each session

### Issue Management
- `issue-prerequisite` - Ensure issue exists (HARD GATE)
- `issue-decomposition` - Break large issues down
- `issue-lifecycle` - Update issues continuously
- `project-status-sync` - Update GitHub Project fields
- `acceptance-criteria-verification` - Verify and report

### Branch/Git
- `branch-discipline` - Never work on main (HARD GATE)
- `clean-commits` - Atomic, descriptive commits

### Research/Memory
- `research-after-failure` - Research after 2 failures
- `pre-work-research` - Research before coding
- `memory-integration` - Use episodic + knowledge graph

### Development Standards
- `strict-typing` - No `any` types ever
- `style-guide-adherence` - Follow Google style guides
- `inline-documentation` - Complete JSDoc/docstrings
- `inclusive-language` - Respectful terminology
- `tdd-full-coverage` - RED-GREEN-REFACTOR
- `no-deferred-work` - No TODOs

### Code Review
- `comprehensive-review` - 7-criteria review
- `review-scope` - Minor vs major
- `apply-all-findings` - Fix ALL findings

### PR/CI
- `pr-creation` - Complete PR documentation
- `ci-monitoring` - Watch and fix CI
- `verification-before-merge` - All gates green (HARD GATE)

### Recovery
- `error-recovery` - Handle failures
- `environment-bootstrap` - Dev environment setup
- `conflict-resolution` - Merge conflicts

## Skill Usage

When a skill applies, load it with the Skill tool:

```
I'm using the issue-driven-development skill to implement this feature.
```

Then follow the skill's instructions exactly.

## GitHub Project Fields

Issues should have these project fields:

| Field | Values |
|-------|--------|
| Status | Backlog, Ready, In Progress, In Review, Done, Blocked |
| Verification | Not Verified, Failing, Partial, Passing |
| Priority | Critical, High, Medium, Low |
| Type | Feature, Bug, Chore, Research, Spike |

## Issue Labels

| Label | Purpose |
|-------|---------|
| `parent` | Has sub-issues |
| `sub-issue` | Child of parent |
| `blocked` | Cannot proceed |
| `needs-research` | Research required |
| `verified` | E2E verified |
