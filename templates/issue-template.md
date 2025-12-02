# GitHub Issue Template

Use this template when creating issues. Copy into `.github/ISSUE_TEMPLATE/feature.md` or use directly.

---

```markdown
---
name: Feature Request
about: A new feature or enhancement
title: '[Feature] '
labels: ''
assignees: ''
---

## Description

[Clear, concise description of what this issue delivers]

## Acceptance Criteria

<!-- Each criterion is a verifiable behavior. Use checkboxes. -->
<!-- These will be checked off during development and verified at completion. -->

- [ ] [First verifiable behavior]
- [ ] [Second verifiable behavior]
- [ ] [Third verifiable behavior]

## Verification Steps

<!-- How to manually verify this feature works. Step-by-step. -->

1. [First step]
2. [Second step]
3. [Expected outcome]

## Technical Notes

<!-- Implementation guidance, constraints, dependencies -->

- [Note 1]
- [Note 2]

## Out of Scope

<!-- Explicitly list what this issue does NOT include -->

- [Not included 1]
- [Not included 2]

## Related Issues

<!-- Link to parent, sub-issues, or related work -->

- Parent: #
- Blocks: #
- Blocked by: #
```

---

## Field Mapping

When this issue is added to a GitHub Project, set these fields:

| Field | Value |
|-------|-------|
| Status | `Backlog` (initial) |
| Verification | `Not Verified` (initial) |
| Criteria Met | `0` |
| Criteria Total | [count of acceptance criteria] |
| Priority | [as appropriate] |
| Type | `Feature` / `Bug` / `Chore` / `Research` / `Spike` |

## Labels

Apply as appropriate:

- `parent` - if this issue will have sub-issues
- `sub-issue` - if this is a child of another issue
- `needs-research` - if research required before work
