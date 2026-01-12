---
name: worker-protocol
description: Defines behavior protocol for spawned worker agents. Injected into worker prompts. Covers startup, progress reporting, exit conditions, and handover preparation.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - mcp__github__*
  - mcp__git__*
  - mcp__memory__*
model: opus
---

# Worker Protocol

Behavioral contract for spawned worker agents. Embedded in worker prompts by `worker-dispatch`.

**Core principle:** Single-purpose, self-documenting, graceful exit.

## Worker Identity

| Property | Example | Purpose |
|----------|---------|---------|
| worker_id | `worker-1701523200-123` | Unique identifier |
| issue | `123` | Assigned issue |
| attempt | `1` | Which attempt |

## Startup

1. Verify branch: `git branch --show-current` (should be `feature/[ISSUE]-*`)
2. Check worktree clean: `git status`
3. Run baseline tests: `pnpm test` or equivalent
4. Post startup comment to issue

**Startup comment:**
```markdown
**Worker Started:** `[WORKER_ID]` | Attempt [N] | Branch `[BRANCH]`
Understanding: [1 sentence summary]
Approach: [brief plan]
```

## Progress Reporting

Post to issue on: **start**, **milestone**, **blocker**, **completion**

```markdown
**Status:** [Implementing|Testing|Blocked|Complete] | Turns: [N]/100
- [x] Completed item
- [ ] Current item
```

## Exit Conditions

Exit when ANY occurs. Return structured JSON:

```json
{"status": "COMPLETED|BLOCKED|HANDOVER", "pr": null, "summary": "..."}
```

| Status | Condition | Action Before Exit |
|--------|-----------|-------------------|
| COMPLETED | PR created, tests pass | Post completion comment |
| BLOCKED | Cannot proceed without external input | Document blocker, what was tried |
| HANDOVER | Turn count 90+ | Post full handover to issue |

## Review Gate (MANDATORY)

**Before creating ANY PR:**

1. Complete `comprehensive-review` (7 criteria)
2. Post review artifact to issue: `<!-- REVIEW:START --> ... <!-- REVIEW:END -->`
3. Address ALL findings (Unaddressed: 0)
4. Status: COMPLETE

**PreToolUse hook BLOCKS `gh pr create` without valid review artifact.**

### Security-Sensitive Files

If modifying: `**/auth/**`, `**/api/**`, `**/*password*`, `**/*token*`, `**/*secret*`

→ Complete `security-review` and include in artifact.

## Behavioral Rules

**DO:**
- Work ONLY on assigned issue
- TDD: tests first
- Commit frequently with descriptive messages
- Post progress to issue
- Complete review before PR
- Handover at 90+ turns

**DO NOT:**
- Start other issues
- Modify unrelated code
- Skip tests
- Create PR without review artifact
- Continue past 100 turns

## Commit Format

```
[type]: [description] (#[ISSUE])

Worker: [WORKER_ID]
```

Types: `feat`, `fix`, `test`, `refactor`, `docs`

## PR Creation

**Prerequisite:** Review artifact in issue comments with status COMPLETE.

```bash
# Verify review exists
gh api "/repos/$OWNER/$REPO/issues/$ISSUE/comments" \
  --jq '[.[] | select(.body | contains("<!-- REVIEW:START -->"))] | length'
```

**PR body:**
```markdown
## Summary
[1-2 sentences]

Closes #[ISSUE]

## Changes
- [Change 1]
- [Change 2]

## Review
Review artifact: See issue #[ISSUE]

---
Worker: `[WORKER_ID]`
```

## Turn Awareness

| Turns | Action |
|-------|--------|
| 0-80 | Normal work |
| 80-90 | Monitor, prepare handover if needed |
| 90+ | Finalize and handover |

## Handover Trigger

At 90+ turns or when context valuable for next attempt:

1. Post handover to issue with `<!-- HANDOVER:START -->` markers
2. Commit all work
3. Exit with `{"status": "HANDOVER", ...}`

See `worker-handover` for full format.

## Integration

**Workers MUST follow these skills:**

| Skill | Purpose |
|-------|---------|
| `issue-driven-development` | Core workflow |
| `strict-typing` | Type requirements (no `any`) |
| `ipv6-first` | Network requirements |
| `tdd-full-coverage` | Testing approach |
| `clean-commits` | Commit standards |
| `worker-handover` | Handover format |
| `comprehensive-review` | Code review (MANDATORY before PR) |
| `apply-all-findings` | Address all review findings |
| `security-review` | For security-sensitive files |
| `deferred-finding` | For tracking deferred findings |
| `review-gate` | PR creation gate |

**Enforced by:** `PreToolUse` hook on `gh pr create`, `Stop` hook for review verification
