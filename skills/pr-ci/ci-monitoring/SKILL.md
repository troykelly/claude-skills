---
name: ci-monitoring
description: Use after creating PR - monitor CI pipeline, resolve failures cyclically until green or issue is identified as unresolvable
---

# CI Monitoring

## Overview

Monitor CI pipeline and resolve failures until green.

**Core principle:** CI failures are blockers. Resolve them before proceeding.

**Announce at start:** "I'm monitoring CI and will resolve any failures."

## The CI Loop

```
PR Created
     │
     ▼
┌─────────────┐
│ Wait for CI │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ CI Status?  │
└──────┬──────┘
       │
   ┌───┴───┐
   │       │
 Green   Red/Failed
   │       │
   ▼       ▼
 DONE   ┌─────────────┐
        │ Diagnose    │
        │ failure     │
        └──────┬──────┘
               │
               ▼
        ┌─────────────┐
        │ Fixable?    │
        └──────┬──────┘
               │
          ┌────┴────┐
          │         │
         Yes        No
          │         │
          ▼         ▼
     ┌─────────┐  ┌─────────────┐
     │ Fix and │  │ Document as │
     │ push    │  │ unresolvable│
     └────┬────┘  └─────────────┘
          │
          └────► Back to "Wait for CI"
```

## Checking CI Status

### Using GitHub CLI

```bash
# Check all CI checks
gh pr checks [PR_NUMBER]

# Watch CI in real-time
gh pr checks [PR_NUMBER] --watch

# Get detailed status
gh pr view [PR_NUMBER] --json statusCheckRollup
```

### Expected Output

```
All checks were successful
0 failing, 0 pending, 5 passing

CHECKS
✓  build          1m23s
✓  lint           45s
✓  test           3m12s
✓  typecheck      1m05s
✓  security-scan  2m30s
```

## Handling Failures

### Step 1: Identify the Failure

```bash
# Get failed check details
gh pr checks [PR_NUMBER]

# View workflow run logs
gh run view [RUN_ID] --log-failed
```

### Step 2: Diagnose the Cause

Common failure types:

| Type | Symptoms | Cause |
|------|----------|-------|
| Test failure | `FAIL` in test output | Code bug or test bug |
| Build failure | Compilation errors | Type errors, syntax errors |
| Lint failure | Style violations | Formatting, conventions |
| Typecheck failure | Type errors | Missing types, wrong types |
| Timeout | Job exceeded time limit | Performance issue or stuck test |
| Flaky test | Passes locally, fails CI | Race condition, environment difference |

### Step 3: Fix the Issue

#### Test Failures

```bash
# Reproduce locally
npm test

# Run specific failing test
npm test -- --grep "test name"

# Fix the code or test
# Commit and push
```

#### Build Failures

```bash
# Reproduce locally
npm run build

# Fix compilation errors
# Commit and push
```

#### Lint Failures

```bash
# Check lint errors
npm run lint

# Auto-fix what's possible
npm run lint:fix

# Manually fix remaining
# Commit and push
```

#### Type Failures

```bash
# Check type errors
npm run typecheck

# Fix type issues
# Commit and push
```

### Step 4: Push Fix and Wait

```bash
# Commit fix
git add .
git commit -m "fix(ci): Resolve test failure in user validation"

# Push
git push

# Wait for CI again
gh pr checks [PR_NUMBER] --watch
```

### Step 5: Repeat Until Green

Loop through diagnose → fix → push → wait until all checks pass.

## Flaky Tests

### Identifying Flakiness

```
Test passes locally
Test fails in CI
Test passes on retry in CI
```

### Handling Flakiness

1. **Don't just retry** - Find the root cause
2. **Check for race conditions** - Timing-dependent code
3. **Check for environment differences** - Paths, env vars, services
4. **Check for state pollution** - Tests affecting each other

```typescript
// Common flaky pattern: timing dependency
// BAD
await saveData();
await delay(100);  // Hoping 100ms is enough
const result = await loadData();

// GOOD: Wait for condition
await saveData();
await waitFor(() => dataExists());
const result = await loadData();
```

## Unresolvable Failures

Sometimes failures can't be fixed in the current PR:

### Legitimate Unresolvable Cases

| Case | Example |
|------|---------|
| CI infrastructure issue | Service down, rate limited |
| Pre-existing flaky test | Not introduced by this PR |
| Upstream dependency issue | External API changed |
| Requires manual intervention | Needs secrets, permissions |

### Process for Unresolvable

1. **Document the issue**

```bash
gh pr comment [PR_NUMBER] --body "## CI Issue

The \`security-scan\` check is failing due to a known issue with the scanner service (see #999).

This is not related to changes in this PR. The scan passes when run locally.

Requesting bypass approval from @maintainer."
```

2. **Create issue if new**

```bash
gh issue create \
  --title "CI: Security scanner service timeout" \
  --body "The security scanner is timing out in CI..."
```

3. **Request bypass if appropriate**

Some teams allow merging with known infrastructure failures.

4. **Do NOT merge with real failures**

If the failure is from your code, it must be fixed.

## CI Best Practices

### Run Locally First

Before pushing:

```bash
# Run the same checks CI will run
npm run lint
npm run typecheck
npm test
npm run build
```

### Commit Incrementally

Don't push 10 commits at once. Push smaller changes:

```bash
# Small fix, push, verify
git push

# Wait for CI
gh pr checks --watch

# Then next change
```

### Monitor Actively

Don't "push and forget":

```bash
# Watch CI after each push
gh pr checks [PR_NUMBER] --watch
```

## Checklist

For each CI run:

- [ ] Waited for CI to complete
- [ ] All checks examined
- [ ] Failures diagnosed
- [ ] Fixes implemented
- [ ] Re-pushed and re-checked
- [ ] All green before proceeding

For unresolvable issues:

- [ ] Root cause identified
- [ ] Not caused by PR changes
- [ ] Documented in PR comment
- [ ] Issue created if new problem
- [ ] Bypass approval requested if appropriate

## Integration

This skill is called by:
- `issue-driven-development` - Step 13

This skill follows:
- `pr-creation` - PR exists

This skill precedes:
- `verification-before-merge` - Final checks

This skill may trigger:
- `error-recovery` - If CI reveals deeper issues
