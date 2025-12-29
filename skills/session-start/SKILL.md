---
name: session-start
description: Use at the beginning of every work session - establishes context by checking GitHub project state, reading memory, verifying environment, and orienting before starting work
---

# Session Start

## Overview

Get your bearings before doing any work. Every session starts here.

**Core principle:** Understand the current state before taking action.

**Announce at start:** "I'm using session-start to get oriented before beginning work."

## The Protocol

Execute these steps in order at the start of every session:

### Step 1: Environment Check

Verify required tools and environment variables are available.

```bash
# Check GitHub CLI authentication
gh auth status

# Check git is available
git --version

# Verify GITHUB_PROJECT is set
echo $GITHUB_PROJECT
```

**If any check fails:** Report to user before proceeding.

**Skill:** `environment-bootstrap`

---

### Step 1.5: Development Services

Check for available development services (docker-compose).

```bash
# Detect compose services
if [ -f "docker-compose.yml" ] || [ -f ".devcontainer/docker-compose.yml" ]; then
    docker-compose config --services
    docker-compose ps
fi
```

**Key questions:**
- What services are available (postgres, redis, etc.)?
- Which are currently running?
- Do any need to be started for this work?

**If services are available but not running:**
```bash
# Start all services
docker-compose up -d

# Or start specific service
docker-compose up -d postgres
```

**Skill:** `local-service-testing`

---

### Step 2: Repository State

Understand the current state of the repository.

```bash
# Current branch
git branch --show-current

# Working directory status
git status

# Recent commits
git log --oneline -5

# Any stashed changes?
git stash list
```

**Key questions:**
- Am I on a feature branch or main?
- Are there uncommitted changes?
- Is there work in progress?

---

### Step 3: GitHub Project State

Check the current state of work in the GitHub Project.

```bash
# Get project items (requires GITHUB_PROJECT to be set)
gh project item-list [PROJECT_NUMBER] --owner @me --format json

# Or check specific issue if provided
gh issue view [ISSUE_NUMBER] --json state,title,labels,projectItems
```

**Key questions:**
- What issues are "In Progress"?
- Are there any blocked items?
- What's the next priority item?

---

### Step 4: Memory Recall

Search for relevant context from previous sessions.

**Episodic Memory:**
- Search for current issue number
- Search for feature/project name
- Search for recent work in this repository

**Knowledge Graph (mcp__memory):**
- Check for entities related to this project
- Look for documented decisions or patterns

**Skill:** `memory-integration`

---

### Step 5: Active Work Detection

Determine if there's work in progress to resume.

**Indicators of active work:**
- Branch is not main
- Uncommitted changes exist
- Issue marked "In Progress" in project
- Previous session notes reference ongoing work

**If active work detected:**
1. Read the associated issue
2. Check last commit message for context
3. Review any verification reports
4. Determine current step in `issue-driven-development` process

---

### Step 6: Environment Bootstrap

If starting fresh or environment needs setup:

```bash
# Run init script if it exists
if [ -f scripts/init.sh ]; then
    ./scripts/init.sh
fi

# Or common alternatives
npm ci        # Node projects
pip install   # Python projects
```

**Verify basic functionality works before starting new work.**

**Skill:** `environment-bootstrap`

---

### Step 7: Orient and Report

Summarize current state to user:

```markdown
## Session State

**Repository:** [owner/repo]
**Branch:** [current branch]
**Working Directory:** [clean/dirty]

**Active Work:**
- Issue: #[number] - [title]
- Status: [project status]
- Progress: [what's been done]

**Environment:**
- [tool versions]
- [any issues detected]

**Development Services:**
- postgres: [running/stopped] @ localhost:5432
- redis: [running/stopped] @ localhost:6379
- [other services from docker-compose]

**Ready to:** [resume work on X / start new issue / await instructions]
```

---

## Decision Tree

```
Start Session
     │
     ▼
┌─────────────────┐
│ Environment OK? │──No──► Report issues, await fix
└────────┬────────┘
         │ Yes
         ▼
┌─────────────────┐
│ On main branch? │──Yes──► Ready for new work
└────────┬────────┘
         │ No
         ▼
┌─────────────────┐
│ Uncommitted     │──Yes──► Resume in-progress work
│ changes exist?  │
└────────┬────────┘
         │ No
         ▼
┌─────────────────┐
│ Issue marked    │──Yes──► Resume in-progress work
│ In Progress?    │
└────────┬────────┘
         │ No
         ▼
Ready for new work
```

## Resuming In-Progress Work

If resuming work from a previous session:

1. **Read the issue** - Full description and all comments
2. **Check last commit** - What was the last completed step?
3. **Run tests** - Is the codebase in a working state?
4. **Review verification** - What criteria are already met?
5. **Determine next step** - Map to `issue-driven-development` steps

Then continue from the appropriate step in `issue-driven-development`.

## Starting New Work

If no work in progress:

1. Check GitHub Project for highest priority "Ready" item
2. Or await user instructions for which issue to work on
3. Begin `issue-driven-development` from Step 1

## Common Issues

| Issue | Resolution |
|-------|------------|
| GITHUB_PROJECT not set | Ask user for project URL |
| Not authenticated to gh | Run `gh auth login` |
| Dirty working directory on main | Stash or discard before proceeding |
| Issue "In Progress" but branch deleted | Reset issue status, start fresh |

## Checklist

Before proceeding to work:

- [ ] Environment verified (gh, git, env vars)
- [ ] Development services detected and status reported
- [ ] Repository state understood
- [ ] GitHub Project state checked
- [ ] Memory searched for context
- [ ] Active work detected or new work identified
- [ ] Environment bootstrapped if needed
- [ ] Required services started (if applicable)
- [ ] State reported to user

## Integration

After session-start completes, proceed to either:

- **Resume:** Continue from current step in `issue-driven-development`
- **New work:** Begin `issue-driven-development` from Step 1

Always operate under `autonomous-operation` mode.
