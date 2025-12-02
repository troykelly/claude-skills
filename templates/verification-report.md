# Verification Report Template

Post this as a comment on the GitHub issue after running verification.

---

```markdown
## Verification Report

**Run**: [ISO 8601 timestamp, e.g., 2024-12-02T14:30:00Z]
**By**: [agent / human / ci]
**Commit**: [short SHA]
**Branch**: [branch name]

### Environment

- Node: [version]
- OS: [platform]
- Browser: [if E2E testing]

### Results

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | [Criterion from acceptance criteria] | PASS / FAIL / PARTIAL / SKIP | [Details] |
| 2 | [Criterion from acceptance criteria] | PASS / FAIL / PARTIAL / SKIP | [Details] |
| 3 | [Criterion from acceptance criteria] | PASS / FAIL / PARTIAL / SKIP | [Details] |

### Summary

| Status | Count |
|--------|-------|
| PASS | X |
| FAIL | X |
| PARTIAL | X |
| SKIP | X |
| **Total** | **X** |

### Test Output

<details>
<summary>Unit Tests</summary>

\`\`\`
[test output]
\`\`\`

</details>

<details>
<summary>Integration Tests</summary>

\`\`\`
[test output]
\`\`\`

</details>

<details>
<summary>E2E Tests</summary>

\`\`\`
[test output or screenshots]
\`\`\`

</details>

### Screenshots

<!-- If E2E verification, include relevant screenshots -->

| Description | Screenshot |
|-------------|------------|
| [What it shows] | ![Screenshot](url) |

### Next Steps

<!-- Only if there are failures or partials -->

- [ ] [Action item 1]
- [ ] [Action item 2]

### Verification Checklist

- [ ] All acceptance criteria evaluated
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] E2E verification complete (if applicable)
- [ ] No regressions detected
- [ ] Documentation updated (if applicable)
```

---

## Status Definitions

| Status | Meaning |
|--------|---------|
| **PASS** | Criterion fully met, verified working |
| **FAIL** | Criterion not met, requires fix |
| **PARTIAL** | Criterion partially met, works with issues |
| **SKIP** | Could not verify (blocked, N/A, etc.) |

## After Posting

Update the GitHub Project fields:

| Field | Update To |
|-------|-----------|
| Verification | `Passing` / `Failing` / `Partial` based on results |
| Criteria Met | Count of PASS |
| Last Verified | Current timestamp |
| Verified By | `agent` / `human` / `ci` |

If all criteria PASS:
- Add `verified` label to issue
- Update Status to `In Review` or `Done` as appropriate
