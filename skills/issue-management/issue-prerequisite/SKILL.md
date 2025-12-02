---
name: issue-prerequisite
description: Use before starting ANY work - hard gate ensuring a GitHub issue exists, creating one if needed through user questioning
---

# Issue Prerequisite

## Overview

No work without a GitHub issue. This is a hard gate.

**Core principle:** Every task, regardless of size, must have a corresponding GitHub issue.

**Announce at start:** "I'm checking for a GitHub issue before proceeding with any work."

## The Gate

```
┌─────────────────────────────────────┐
│         WORK REQUESTED              │
└─────────────────┬───────────────────┘
                  │
                  ▼
        ┌─────────────────┐
        │ Issue provided? │
        └────────┬────────┘
                 │
       ┌─────────┴─────────┐
       │                   │
      Yes                  No
       │                   │
       ▼                   ▼
  ┌─────────┐      ┌─────────────┐
  │ Verify  │      │ Ask user or │
  │ issue   │      │ create issue│
  │ exists  │      └──────┬──────┘
  └────┬────┘             │
       │                  │
       ▼                  ▼
  ┌──────────────────────────────┐
  │     Issue confirmed?         │
  │   (exists and accessible)    │
  └─────────────┬────────────────┘
                │
       ┌────────┴────────┐
       │                 │
      Yes                No
       │                 │
       ▼                 ▼
   PROCEED            STOP
   WITH WORK       (Cannot proceed)
```

## When Issue is Provided

Verify the issue exists and is accessible:

```bash
# Verify issue exists
gh issue view [ISSUE_NUMBER] --json number,title,state,body

# Check issue is in the correct repository
gh issue view [ISSUE_NUMBER] --json url
```

**If issue doesn't exist or is inaccessible:**
- Report error to user
- Do not proceed

## When No Issue is Provided

### Option 1: User has existing issue

Ask: "What's the GitHub issue number for this work?"

### Option 2: Need to create issue

Gather information to create an issue:

```markdown
I need to create a GitHub issue before starting this work.

**Please provide or confirm:**

1. **Title:** [What should this issue be called?]

2. **Description:** [What should this issue deliver?]

3. **Acceptance Criteria:**
   - [ ] [First verifiable behavior]
   - [ ] [Second verifiable behavior]

4. **Type:** Feature / Bug / Chore / Research / Spike

5. **Priority:** Critical / High / Medium / Low
```

### Creating the Issue

Once information is gathered:

```bash
# Create the issue
gh issue create \
  --title "[Type] Title here" \
  --body "## Description

[Description]

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Verification Steps

1. Step 1
2. Step 2

## Technical Notes

[Any technical context]"

# Add to project
gh project item-add [PROJECT_NUMBER] --owner @me --url [ISSUE_URL]

# Set project fields
gh project item-edit --project-id [PROJECT_ID] --id [ITEM_ID] \
  --field-id [STATUS_FIELD_ID] --single-select-option-id [READY_OPTION_ID]
```

## Issue Quality Check

Before proceeding, verify the issue has:

| Required | Check |
|----------|-------|
| Clear title | Describes what will be delivered |
| Description | Explains the work |
| Acceptance criteria | At least one verifiable criterion |
| In GitHub Project | Added with correct status |

If any are missing, update the issue before proceeding.

## "Too Small for an Issue" is False

Common objections and responses:

| Objection | Response |
|-----------|----------|
| "It's just a typo fix" | Issues take 30 seconds. They provide a record. Create one. |
| "It's a one-liner" | One-liners can introduce bugs. Document them. |
| "I'll do it quickly" | Quick work is forgotten work. Track it. |
| "It's obvious what needs doing" | If it's obvious, the issue will be fast to write. |

No exceptions. Every change has an issue.

## Minimum Viable Issue

For truly trivial work, this is the minimum:

```markdown
Title: Fix typo in README.md

## Description
Fix typo: "teh" → "the"

## Acceptance Criteria
- [ ] Typo is corrected
```

That's 30 seconds. There's no excuse.

## After Gate Passes

Once issue is confirmed:

1. Note the issue number for all subsequent work
2. Proceed to next step in `issue-driven-development`
3. Reference issue in all commits and PR

## Checklist

Before proceeding past this gate:

- [ ] Issue number identified
- [ ] Issue exists in GitHub
- [ ] Issue is accessible (correct repo, not archived)
- [ ] Issue has description
- [ ] Issue has at least one acceptance criterion
- [ ] Issue is in GitHub Project
