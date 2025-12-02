---
name: apply-all-findings
description: Use after code review - implement ALL recommendations regardless of severity; no finding is too minor to address
---

# Apply All Findings

## Overview

Implement EVERY finding from code review. No exceptions for "minor" issues.

**Core principle:** Minor issues accumulate into major problems.

**The rule:** If it was worth noting, it's worth fixing.

## Why All Findings

### Minor Issues Compound

```
1 unclear variable name +
1 missing null check +
1 inconsistent style +
1 outdated comment =
Confusing, fragile code
```

### Selective Fixing Creates Precedent

```
"This minor issue can wait" →
"That minor issue can wait too" →
"We don't fix minor issues" →
Technical debt mountain
```

### Thoroughness Builds Quality Culture

```
Every finding addressed →
High standards maintained →
Quality becomes habit
```

## The Process

### Step 1: Gather All Findings

From `comprehensive-review`, you have:

```markdown
### Findings

1. [Critical] SQL injection in findUser()
2. [Major] N+1 query in getOrders()
3. [Minor] Variable 'x' should be renamed
4. [Minor] Missing JSDoc on helper()
5. [Minor] Inconsistent quote style
```

### Step 2: Create Checklist

Every finding becomes a todo:

```markdown
- [ ] Fix SQL injection in findUser()
- [ ] Fix N+1 query in getOrders()
- [ ] Rename variable 'x' to descriptive name
- [ ] Add JSDoc to helper()
- [ ] Fix quote style to use single quotes
```

### Step 3: Address Systematically

Work through the list:

1. Fix the issue
2. Verify the fix
3. Check off the item
4. Move to next

### Step 4: Verify All Complete

Before considering done:

```bash
# Re-run linting
npm run lint

# Re-run tests
npm test

# Re-run type check
npm run typecheck
```

All checks must pass.

## Addressing by Type

### Critical/Major Findings

These require code changes:

```typescript
// Finding: SQL injection in findUser()
// Before
return db.query(`SELECT * FROM users WHERE username = '${username}'`);

// After
return db.query('SELECT * FROM users WHERE username = ?', [username]);
```

### Minor: Naming

```typescript
// Finding: Variable 'x' should be renamed
// Before
const x = users.filter(u => u.active);

// After
const activeUsers = users.filter(user => user.isActive);
```

### Minor: Documentation

```typescript
// Finding: Missing JSDoc on helper()
// Before
function helper(data: Data): Result {

// After
/**
 * Transforms raw data into the expected result format.
 *
 * @param data - Raw data from the API
 * @returns Transformed result ready for display
 */
function helper(data: Data): Result {
```

### Minor: Style

```typescript
// Finding: Inconsistent quote style
// Before
const name = "Alice";
const greeting = 'Hello';

// After (using project standard: single quotes)
const name = 'Alice';
const greeting = 'Hello';
```

### Minor: Comments

```typescript
// Finding: Outdated comment
// Before
// TODO: Implement error handling
try {
  await save(data);
} catch (error) {
  throw new SaveError('Failed to save', { cause: error });
}

// After (remove outdated TODO, error handling exists)
try {
  await save(data);
} catch (error) {
  throw new SaveError('Failed to save', { cause: error });
}
```

## Handling "Won't Fix"

Very rarely, a finding truly can't be fixed:

### Legitimate Cases

| Case | Example |
|------|---------|
| External constraint | Third-party API requires this format |
| Intentional design | Performance trade-off documented |
| Breaking change scope | Would require major version bump |

### Process for Won't Fix

1. **Document why** it can't be fixed
2. **Get explicit approval** from human partner
3. **Create issue** for future resolution if applicable
4. **Add code comment** explaining the situation

```typescript
// KNOWN ISSUE: Using deprecated API due to external constraint.
// See issue #789 for planned migration when dependency updates.
// Approved by @maintainer on 2024-12-01.
const result = deprecatedMethod(data);
```

### Not Acceptable as "Won't Fix"

| Excuse | Response |
|--------|----------|
| "It's just style" | Style matters. Fix it. |
| "It's too minor" | Minor is still worth fixing. |
| "It works fine" | "Works" isn't "correct". |
| "Nobody will notice" | Future you will notice. |
| "Takes too long" | Technical debt takes longer. |

## Verification

After addressing all findings:

### Run All Checks

```bash
# Linting
npm run lint

# Type checking
npm run typecheck

# Tests
npm test

# Build
npm run build
```

### Review the Diff

```bash
git diff
```

Verify:
- All findings addressed
- No unrelated changes
- Tests updated if behavior changed

### Self-Review Again

Quick pass through 7 criteria to ensure fixes didn't introduce new issues.

## Checklist

Before moving on from review:

- [ ] All critical findings addressed
- [ ] All major findings addressed
- [ ] All minor findings addressed
- [ ] Any "won't fix" has documented approval
- [ ] All automated checks pass
- [ ] Fixes reviewed for correctness
- [ ] No new issues introduced

## Common Pushback (Rejected)

| Pushback | Response |
|----------|----------|
| "We can fix minors later" | Later never comes. Now. |
| "This is slowing us down" | Debt slows you down more. |
| "It's not important" | Then why was it noted? |
| "Good enough" | Good enough is never enough. |
| "The reviewer is being picky" | Attention to detail is valuable. |

## Integration

This skill is called by:
- `issue-driven-development` - Step 10

This skill follows:
- `comprehensive-review` - Generates the findings

This skill ensures:
- No accumulated minor issues
- Consistent quality standards
- Complete reviews, not partial
