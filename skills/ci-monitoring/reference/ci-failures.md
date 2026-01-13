# CI Failures Reference

Detailed patterns for diagnosing and fixing CI failures.

## Identifying Failures

```bash
gh pr checks [PR_NUMBER]
gh run view [RUN_ID] --log-failed
```

## Common Failure Types

| Type | Symptoms | Cause |
|------|----------|-------|
| Test failure | `FAIL` in test output | Code bug or test bug |
| Build failure | Compilation errors | Type errors, syntax errors |
| Lint failure | Style violations | Formatting, conventions |
| Typecheck failure | Type errors | Missing types, wrong types |
| Timeout | Job exceeded time limit | Performance issue or stuck test |
| Flaky test | Passes locally, fails CI | Race condition, environment difference |

## Fix Commands by Type

### Test Failures
```bash
pnpm test
pnpm test --grep "test name"
```

### Build Failures
```bash
pnpm build
```

### Lint Failures
```bash
pnpm lint
pnpm lint:fix
```

### Type Failures
```bash
pnpm typecheck
```

## Push and Wait

```bash
git add .
git commit -m "fix(ci): Resolve [failure type] in [component]"
git push
gh pr checks [PR_NUMBER] --watch
```

## Flaky Tests

Identifying flakiness:
- Test passes locally
- Test fails in CI
- Test passes on retry in CI

Root causes:
1. Race conditions - timing-dependent code
2. Environment differences - paths, env vars, services
3. State pollution - tests affecting each other

```typescript
// BAD: Timing dependency
await saveData();
await delay(100);
const result = await loadData();

// GOOD: Wait for condition
await saveData();
await waitFor(() => dataExists());
const result = await loadData();
```

## Unresolvable Failures

Legitimate cases:
- CI infrastructure issue (service down, rate limited)
- Pre-existing flaky test (not introduced by this PR)
- Upstream dependency issue (external API changed)
- Requires manual intervention (needs secrets, permissions)

Process:
```bash
# Document in PR
gh pr comment [PR_NUMBER] --body "## CI Issue
The \`[check]\` is failing due to [reason]. Not related to this PR."

# Create issue if new
gh issue create --title "CI: [description]" --body "[details]"
```

Do NOT merge with real failures from your code.
