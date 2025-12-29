---
name: worker-handover
description: Defines context handover format when workers hit turn limit. Creates structured handover files that enable replacement workers to continue seamlessly.
---

# Worker Handover

## Overview

When workers approach their turn limit (100 turns), they must create a handover file that enables a replacement worker to continue without losing context.

**Core principle:** A replacement worker should understand the work as well as the original worker did.

**Announce at start:** "I'm approaching my turn limit. Creating handover file for replacement worker."

## When to Handover

| Turns Used | Action |
|------------|--------|
| 85+ | Evaluate if handover needed |
| 90+ | Begin handover preparation |
| 95+ | Complete handover, prepare to exit |
| 100 | Exit (automatic) |

## Handover File Location

```
.orchestrator/handover-[ISSUE].md
```

Or in worktree:
```
[WORKTREE]/.orchestrator/handover-[ISSUE].md
```

## Handover File Format

```markdown
# Handover: Issue #[ISSUE]

## Metadata
| Field | Value |
|-------|-------|
| Issue | #[ISSUE] |
| Previous Worker | [WORKER_ID] |
| Turns Used | [N]/100 |
| Timestamp | [ISO_TIMESTAMP] |
| Orchestration | [ORCHESTRATION_ID] |
| Attempt | [N] |

## Issue Summary
[Concise summary of what the issue requires - in your own words, not copied]

## Current State

### Branch Status
- **Branch:** `[BRANCH_NAME]`
- **Commits:** [N] commits ahead of main
- **Last Commit:** `[COMMIT_HASH]` - [COMMIT_MESSAGE]

### Files Modified
```
[List of modified files with brief description of changes]
```

### Tests Status
- **Passing:** [N]
- **Failing:** [N]
- **Coverage:** [X]%

## Work Completed

### Done
- [x] [Completed task 1]
- [x] [Completed task 2]
- [x] [Completed task 3]

### In Progress
- [ ] [Current task - describe state]

### Remaining
- [ ] [Remaining task 1]
- [ ] [Remaining task 2]

## Context & Decisions

### Key Decisions Made
1. **[Decision]:** [Why this choice was made]
2. **[Decision]:** [Why this choice was made]

### Approaches Tried
1. **[Approach]:** [Result/Why abandoned]
2. **[Approach]:** [Result/Why abandoned]

### Important Discoveries
- [Discovery that affects implementation]
- [Discovery that affects implementation]

## Technical Notes

### Architecture Notes
[Any architectural decisions or patterns being used]

### Gotchas
- [Thing that might trip up the next worker]
- [Non-obvious behavior discovered]

### Dependencies
- [Library/package added and why]
- [API endpoint used and how]

## Current Blocker (if any)
[Description of what's blocking progress, if anything]

## Recommended Next Steps
1. [Specific next action to take]
2. [Following action]
3. [Following action]

## Files to Review First
1. `[path/to/key/file.ts]` - [Why it's important]
2. `[path/to/key/file.ts]` - [Why it's important]

## Commands to Run
```bash
# Verify current state
pnpm test

# Continue development
[specific commands]
```

---
*Handover created by [WORKER_ID] at [TIMESTAMP]*
```

## Creating a Handover

### Step 1: Assess State

```bash
# Check git status
git status
git log --oneline -10

# Check test status
pnpm test 2>&1 | tail -20

# Count modified files
git diff --name-only HEAD~[N]
```

### Step 2: Write Handover File

```bash
mkdir -p .orchestrator

cat > .orchestrator/handover-$ISSUE.md <<'EOF'
# Handover: Issue #$ISSUE
...
EOF
```

### Step 3: Commit Handover

```bash
git add .orchestrator/handover-$ISSUE.md
git commit -m "chore: Create handover file for issue #$ISSUE

Worker $WORKER_ID reached turn limit.
Context preserved for replacement worker.

🤖 Worker: $WORKER_ID"
```

### Step 4: Notify in Issue

```markdown
🤖 **Handover Created** 🔄

**Worker:** [WORKER_ID]
**Turns Used:** [N]/100
**Handover File:** `.orchestrator/handover-[ISSUE].md`

**Work completed:**
- [x] [Item 1]
- [x] [Item 2]

**Remaining:**
- [ ] [Item 3]
- [ ] [Item 4]

A replacement worker will continue with full context.

---
*Orchestration: [ORCHESTRATION_ID]*
```

## Receiving a Handover

When a replacement worker starts with a handover file:

### Step 1: Read Handover

```bash
cat .orchestrator/handover-$ISSUE.md
```

### Step 2: Verify State

```bash
# Verify branch
git branch --show-current

# Check current state matches handover
git status
git log --oneline -5

# Run tests
pnpm test
```

### Step 3: Acknowledge Receipt

Post to issue:

```markdown
🤖 **Handover Received** ✅

**Replacement Worker:** [NEW_WORKER_ID]
**Continuing from:** [PREVIOUS_WORKER_ID]
**Attempt:** [N]

**Handover verified:**
- [x] Branch state matches
- [x] Tests status matches
- [x] Context understood

**Continuing with:**
[First task from "Recommended Next Steps"]

---
*Orchestration: [ORCHESTRATION_ID]*
```

### Step 4: Continue Work

Follow the "Recommended Next Steps" from the handover file.

## Handover Quality Checklist

Before creating handover:

- [ ] All local changes committed
- [ ] Handover file captures current state accurately
- [ ] Key decisions are documented
- [ ] Gotchas are noted
- [ ] Next steps are specific and actionable
- [ ] Files to review are listed in priority order
- [ ] Commands to run are tested and correct
- [ ] Handover committed to branch
- [ ] Issue comment posted

## Bad Handover Examples

### Too Vague

```markdown
## Work Completed
- Did some stuff
- Made progress

## Next Steps
- Finish the feature
```

### Missing Context

```markdown
## Work Completed
- [x] Implemented the thing

## Next Steps
- Fix the tests
```
(No explanation of WHY tests are failing)

## Good Handover Example

```markdown
# Handover: Issue #142 - Dark Mode Support

## Metadata
| Field | Value |
|-------|-------|
| Issue | #142 |
| Previous Worker | worker-1701523200-142 |
| Turns Used | 94/100 |
| Timestamp | 2025-12-02T15:30:00Z |
| Orchestration | orch-2025-12-02-001 |
| Attempt | 1 |

## Issue Summary
Add dark mode toggle to settings page. User preference should persist
across sessions using localStorage. All components need to respect
the theme context.

## Current State

### Branch Status
- **Branch:** `feature/142-dark-mode-support`
- **Commits:** 8 commits ahead of main
- **Last Commit:** `a1b2c3d` - feat: Add ThemeContext and provider

### Files Modified
- `src/contexts/ThemeContext.tsx` - Theme context with dark/light modes
- `src/components/Settings/ThemeToggle.tsx` - Toggle switch component
- `src/hooks/useTheme.ts` - Hook for accessing theme
- `src/styles/themes.ts` - Theme token definitions
- `src/App.tsx` - Wrapped with ThemeProvider

### Tests Status
- **Passing:** 42
- **Failing:** 3
- **Coverage:** 78%

## Work Completed

### Done
- [x] Created ThemeContext with dark/light mode support
- [x] Implemented theme tokens (colors, shadows, etc.)
- [x] Added ThemeProvider to App root
- [x] Created useTheme hook
- [x] Built ThemeToggle component
- [x] Added localStorage persistence

### In Progress
- [ ] Fixing CSS variable application (3 tests failing)

### Remaining
- [ ] Update remaining components to use theme tokens
- [ ] Add system preference detection
- [ ] Add transition animations

## Context & Decisions

### Key Decisions Made
1. **CSS Variables over styled-components theming:** Chose CSS variables
   because they work with existing CSS and don't require wrapping all
   components. Faster runtime switching.

2. **localStorage over cookies:** Theme preference is client-only,
   no need to send to server.

### Approaches Tried
1. **styled-components ThemeProvider:** Abandoned because existing
   components use plain CSS. Would require rewriting all styles.

### Important Discoveries
- The `Header` component has hardcoded colors that need updating
- Dark mode also needs to update the `<meta theme-color>` tag

## Technical Notes

### Architecture Notes
Theme flows: ThemeProvider → useTheme hook → CSS variables on :root

### Gotchas
- CSS variables must be set on `:root`, not `body`
- Some third-party components (DatePicker) ignore our theme

### Dependencies
- No new dependencies added
- Using native CSS custom properties

## Current Blocker
Tests failing because CSS variables aren't being applied in test
environment (jsdom). Need to mock or configure jsdom properly.

## Recommended Next Steps
1. Fix jsdom CSS variable issue - see https://github.com/jsdom/jsdom/issues/1895
2. Update remaining components (Header, Footer, Sidebar)
3. Add prefers-color-scheme media query detection

## Files to Review First
1. `src/contexts/ThemeContext.tsx` - Core theme logic
2. `src/styles/themes.ts` - Token definitions
3. `src/__tests__/ThemeContext.test.tsx` - Failing tests

## Commands to Run
```bash
# Run failing tests
pnpm test --grep "ThemeContext"

# Start dev server to see current state
pnpm dev
```

---
*Handover created by worker-1701523200-142 at 2025-12-02T15:30:00Z*
```

## Integration

This skill is used by:
- `worker-protocol` - Triggers handover creation
- `worker-dispatch` - Provides handover to replacement workers

This skill references:
- `issue-lifecycle` - Issue comment format
