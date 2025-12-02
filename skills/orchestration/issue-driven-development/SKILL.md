---
name: issue-driven-development
description: Use for any development work - the master 13-step coding process that orchestrates all other skills, ensuring GitHub issue tracking, proper branching, TDD, code review, and CI verification
---

# Issue-Driven Development

## Overview

The master coding process. Every step references specific skills. Follow in order.

**Core principle:** No work without an issue. No shortcuts. No exceptions.

**Announce at start:** "I'm using issue-driven-development to implement this work."

## Before Starting

Create TodoWrite items for each step you'll execute. This is not optional.

## The 13-Step Process

### Step 1: Issue Check

**Question:** Am I working on a clearly defined GitHub issue?

**Actions:**
- If no issue exists → Create one using `issue-prerequisite` skill
- If issue is vague → Ask questions, UPDATE the issue, then proceed
- Verify issue is in GitHub Project with correct fields

**Skill:** `issue-prerequisite`

**Gate:** Do not proceed without a GitHub issue URL.

---

### Step 2: Read Comments

**Question:** Are there comments on the issue I need to read?

**Actions:**
- Read all comments on the issue
- Note any decisions, clarifications, or context
- Check for linked issues or PRs

**Skill:** `issue-lifecycle`

---

### Step 3: Size Check

**Question:** Is this issue too large for a single task?

**Indicators of too-large:**
- More than 5 acceptance criteria
- Touches more than 3 unrelated areas
- Estimated > 1 context window of work
- Multiple independent deliverables

**If too large:**
1. Break into sub-issues using `issue-decomposition`
2. Link sub-issues to parent
3. Update parent issue as `parent` label
4. Loop back to Step 1 with first sub-issue

**Skill:** `issue-decomposition`

---

### Step 4: Memory Search

**Question:** Is there previous work on this issue or related issues?

**Actions:**
- Search `episodic-memory` for issue number, feature name, related terms
- Search `mcp__memory` knowledge graph for related entities
- Note any relevant context, decisions, or gotchas

**Skill:** `memory-integration`

---

### Step 5: Research

**Question:** Do I need to perform research to complete this task?

**Research types:**
1. **Repository documentation** - README, CONTRIBUTING, docs/
2. **Existing codebase** - Similar patterns, related code
3. **Online resources** - API docs, library references, Stack Overflow

**Actions:**
- Conduct necessary research
- Document findings in issue comment if significant
- Note any blockers or concerns

**Skill:** `pre-work-research`

---

### Step 6: Branch Check

**Question:** Am I on the correct branch?

**Rules:**
- NEVER work on `main`
- Create feature branch if needed
- Branch from correct base (usually `main`, sometimes existing feature branch)

**Naming:** `feature/issue-123-short-description` or `fix/issue-456-bug-name`

**Skill:** `branch-discipline`

**Gate:** Do not proceed if on `main`.

---

### Step 7: TDD Development

**Process:** RED → GREEN → REFACTOR

**Standards to apply simultaneously:**
- `tdd-full-coverage` - Write test first, watch fail, minimal code to pass
- `strict-typing` - No `any` types, full typing
- `inline-documentation` - JSDoc/docstrings for all public APIs
- `inclusive-language` - Respectful terminology
- `no-deferred-work` - No TODOs, do it now

**Actions:**
- Write failing test for first acceptance criterion
- Implement minimal code to pass
- Refactor if needed
- Repeat for each criterion

**Skills:** `tdd-full-coverage`, `strict-typing`, `inline-documentation`, `inclusive-language`, `no-deferred-work`

---

### Step 8: Verification Loop

**Question:** Did I succeed in delivering what is documented in the issue?

**Actions:**
- Run all tests
- Check each acceptance criterion
- If any failure → Return to Step 7
- If 2 consecutive failures → Trigger `research-after-failure`

**Skill:** `acceptance-criteria-verification`, `research-after-failure`

---

### Step 9: Code Review

**Question:** Minor change or major change?

**Minor change (Step 9.1):**
- Review only new tests and generated code
- Use `comprehensive-review` checklist

**Major change (Step 9.2):**
- Identify all impacted code
- Review new AND impacted tests and code
- Use `comprehensive-review` checklist

**7 Review Criteria:**
1. Blindspots - What am I missing?
2. Clarity/Consistency - Is code readable and consistent?
3. Maintainability - Can this be maintained?
4. Security - Any vulnerabilities?
5. Performance - Any bottlenecks?
6. Documentation - Adequate docs?
7. Style - Follows style guide?

**Skills:** `review-scope`, `comprehensive-review`

---

### Step 10: Implement Findings

**Rule:** Implement ALL recommendations from code review, regardless how minor.

**Actions:**
- Address each finding
- Re-run affected tests
- Update documentation if needed

**Skill:** `apply-all-findings`

---

### Step 11: Run Full Tests

**Actions:**
- Run full relevant test suite (not just new tests)
- Verify no regressions
- Check test coverage if available

**Skill:** `tdd-full-coverage`

---

### Step 12: Raise PR

**Actions:**
- Commit with descriptive message
- Push branch
- Create PR with complete documentation:
  - Summary of changes
  - Link to issue
  - Verification report
  - Screenshots if UI changes

**Skills:** `clean-commits`, `pr-creation`

---

### Step 13: CI Monitoring

**Actions:**
- Wait for CI to run
- If failure → Fix and push
- Repeat until green or truly unresolvable
- If unresolvable → Document in issue, mark as blocked

**Skills:** `ci-monitoring`, `verification-before-merge`

---

## Throughout the Process

**Issue updates happen CONTINUOUSLY, not as a separate step.**

At minimum, update the issue:
- When starting work (Status → In Progress)
- When hitting blockers
- When making significant decisions
- When completing verification
- When raising PR

**Skill:** `issue-lifecycle`, `project-status-sync`

## Error Handling

If any step fails unexpectedly:

1. Assess severity using `error-recovery`
2. Preserve evidence (logs, errors)
3. Attempt recovery if possible
4. If unrecoverable, update issue as Blocked and report

**Skill:** `error-recovery`

## Completion Criteria

Work is complete when:

- [ ] All acceptance criteria verified (PASS)
- [ ] All tests pass
- [ ] Build succeeds
- [ ] PR created with complete documentation
- [ ] CI is green
- [ ] Issue status updated
- [ ] GitHub Project fields updated

## Quick Reference

| Step | Skill(s) | Gate |
|------|----------|------|
| 1 | issue-prerequisite | Must have issue |
| 2 | issue-lifecycle | - |
| 3 | issue-decomposition | - |
| 4 | memory-integration | - |
| 5 | pre-work-research | - |
| 6 | branch-discipline | Must not be on main |
| 7 | tdd-full-coverage, strict-typing, inline-documentation, inclusive-language, no-deferred-work | - |
| 8 | acceptance-criteria-verification, research-after-failure | - |
| 9 | review-scope, comprehensive-review | - |
| 10 | apply-all-findings | - |
| 11 | tdd-full-coverage | - |
| 12 | clean-commits, pr-creation | - |
| 13 | ci-monitoring, verification-before-merge | Must be green |
