# Review Feedback Reference

Detailed commands and patterns for handling PR review feedback.

## Detecting Unresolved Threads

```bash
OWNER="[OWNER]"
REPO="[REPO]"
PR_NUMBER=[PR_NUMBER]

gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 1) {
            nodes {
              body
              author { login }
              path
              line
            }
          }
        }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F pr=$PR_NUMBER
```

Filter: `isResolved: false` = needs attention.

## Evaluating Feedback

Apply `receiving-code-review` skill principles:

| Step | Action |
|------|--------|
| Read | Understand the complete feedback |
| Verify | Is this technically correct for THIS codebase? |
| Evaluate | Valid concern? Outdated? Wrong context? |
| Decide | Fix, defer, or push back with reasoning |

Questions to ask:
- Does this break existing functionality?
- Does the reviewer understand the full context?
- Is this a real security/correctness issue?
- Is this stylistic preference vs real problem?

## Replying in Thread

Reply directly in the review thread (not top-level PR comment):

```bash
COMMENT_ID=[COMMENT_ID]

gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies \
  -f body="Fixed. [Brief description]. Changes in [commit_sha]."
```

**For pushback:**
```markdown
This doesn't apply here because [technical reason].
[Evidence: link to code, test, or documentation]
```

## Resolving Threads

```bash
THREAD_ID="[THREAD_ID]"  # e.g., PRRT_kwDOQ0bMHs5pFTSB

gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId="$THREAD_ID"
```

## Automated Reviewer Categories

| Category | Typical Flags | Response |
|----------|---------------|----------|
| Security | Injection, auth bypass, data leaks | Fix immediately |
| Performance | N+1 queries, memory leaks | Evaluate in context |
| Style | Naming, formatting | Follow project standards |
| Complexity | Long functions, deep nesting | Evaluate tradeoffs |

## Deferring Feedback

For valid feedback out of scope for this PR:

```bash
# Create tracking issue
gh issue create \
  --title "[Tech Debt] Review feedback from PR #[PR_NUMBER]: [SUMMARY]" \
  --body "From automated review on PR #[PR_NUMBER].

## Feedback
[PASTE FEEDBACK]

## Reason for Deferral
[WHY NOT IN THIS PR]"

# Reply with issue link
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies \
  -f body="Valid point. Created #[ISSUE_NUMBER] to track this separately."

# Resolve thread
gh api graphql -f query='mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } } }' -f threadId="$THREAD_ID"
```
