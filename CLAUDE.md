# Claude Code Development Instructions

This file governs how Claude instances work on this repository. This is a Claude Code plugin containing skills for issue-driven development.

## Foundational Principle

**Your training data is over two years old. You do not know current APIs, patterns, or best practices without research.**

This is not a suggestion. This is reality. Act accordingly.

## The Contract

Working on this repository requires:

1. **Research before any action** - No modifications, no new code, no assumptions without current information
2. **Slow, methodical work** - Speed is not a value here. Thoroughness is.
3. **No corner-cutting** - Any shortcut is a failure. Stop and redo.
4. **Verify everything** - Claims of completion require proof

If you cannot commit to these principles, do not proceed.

---

## Research-First Methodology

### The Rule

**Research before ANY action.** Before writing or modifying any skill, you must research:

1. Current Claude Code documentation
2. Current plugin APIs and patterns
3. Current skill authoring conventions

No assumptions from training data. Your knowledge is stale.

### Research Source Priority

When researching, use this order:

| Priority | Source | Method |
|----------|--------|--------|
| 1 | Official Claude Code documentation | Use `claude-code-guide` agent or fetch official docs |
| 2 | This repository's existing patterns | Read existing skills, understand conventions |
| 3 | Web search for current information | Search for recent changes, API updates, best practices |

### Research Protocol

Before ANY modification or creation:

```
1. STOP - Do not write anything yet
2. RESEARCH - Gather current information from all three sources
3. DOCUMENT - Note what you learned and how it applies
4. VERIFY - Confirm your understanding is current and correct
5. THEN PROCEED - Only now may you begin work
```

### Announce Your Research

At the start of any task, announce:

> "I am researching current Claude Code documentation, existing patterns in this repository, and current best practices before proceeding."

This is not optional. This is the protocol.

---

## Slow and Methodical Work

### What This Means

- Read before writing
- Understand before modifying
- Verify before claiming completion
- One logical step at a time
- No batch changes without individual verification

### Prohibited Actions (Corner-Cutting)

The following are **failures** that require stopping and redoing:

| Prohibited Action | Why It's Prohibited |
|-------------------|---------------------|
| Writing code without reading existing patterns first | You don't know what patterns exist |
| Assuming API behavior from training data | Your knowledge is stale |
| Skipping tests or verification | Unverified work is incomplete work |
| Making multiple unrelated changes in one commit | Cannot verify or revert atomically |
| Claiming completion without explicit verification | Claims require proof |
| Proceeding when uncertain without researching first | Uncertainty means you lack information |
| Copying patterns without understanding them | Cargo-culting creates fragile code |
| Rushing to show progress | Speed is not valued here |
| Batching updates instead of continuous progress | Hides problems and delays feedback |
| Modifying a skill without reading it completely first | You cannot improve what you don't understand |

### The Spirit of the Rule

These prohibitions catch known failure modes. But they are not exhaustive.

The spirit is: **if an action prioritizes speed over thoroughness, it is wrong.**

If you find yourself thinking "I can skip this because it's not explicitly prohibited," you have already failed. Stop and reconsider.

---

## Understand-Before-Modify Rule

### For Existing Skills

Before modifying ANY existing skill:

1. **Read the entire skill** - Every line, not just the section you're changing
2. **Summarize its purpose** - In your own words, what does this skill do?
3. **Identify integration points** - What other skills call this? What does this call?
4. **Understand the patterns used** - What conventions does it follow?
5. **Only then modify** - Changes must preserve intent unless explicitly asked to change it

### For New Skills

Before creating ANY new skill:

1. **Research current skill authoring patterns** - How are skills structured now?
2. **Read 2-3 similar existing skills** - What patterns do they use?
3. **Identify where it fits** - What category? What skills will it integrate with?
4. **Draft the structure first** - Get the skeleton right before filling in details
5. **Verify against existing patterns** - Does it match conventions?

---

## Verification Requirements

### Before Claiming Completion

You must verify AND explicitly document:

| Verification | How to Verify |
|--------------|---------------|
| Skill loads correctly | Test that the skill can be invoked |
| Follows established patterns | Compare against existing skills in this repo |
| Documentation is complete | All sections present, no placeholders |
| No stale assumptions | Every claim backed by current research |
| Integration points work | Referenced skills exist and are compatible |
| Frontmatter is correct | name, description fields present and accurate |

### Verification Statement

When claiming completion, provide an explicit verification statement:

```markdown
## Verification Complete

- [ ] Skill loads: [Tested by/method]
- [ ] Patterns followed: [Compared against: skill1, skill2]
- [ ] Documentation complete: [All sections present]
- [ ] Research backing: [Sources consulted]
- [ ] Integration verified: [Skills tested]
- [ ] Frontmatter correct: [name and description verified]
```

Do not claim completion without this statement.

---

## Handling Uncertainty

### The Protocol

When you encounter something you're unsure about:

```
1. STOP - Do not guess
2. RESEARCH - Attempt to resolve through research
   - Check official documentation
   - Check existing patterns in this repo
   - Search for current information
3. IF STILL UNCERTAIN - Ask the user
   - Explain what you're uncertain about
   - Explain what you researched
   - Ask for guidance before proceeding
4. NEVER GUESS - Guessing is a failure
```

### Uncertainty Triggers

If any of these apply, you are uncertain and must follow the protocol:

- "I think this might work..."
- "Based on my training, I believe..."
- "This should be correct..."
- "I'm not 100% sure, but..."
- "This is probably how it works..."

These phrases indicate stale knowledge or assumptions. Research first.

---

## Commit and Progress Discipline

### Atomic Commits

Each logical unit of work gets its own commit:

- One skill creation = one commit
- One skill modification = one commit
- One documentation update = one commit
- One bug fix = one commit

Do not batch unrelated changes. Each commit should be independently understandable and revertible.

### Continuous Updates

Update progress continuously, not at the end:

- Comment on issues at each significant milestone
- Update status as work progresses
- Document blockers immediately when encountered
- Do not wait until completion to report progress

### Commit Message Format

```
<type>: <description>

<body explaining what and why>

Research: <sources consulted>
Verified: <what was verified>
```

Types: `feat`, `fix`, `docs`, `refactor`, `chore`

---

## Skill Structure Standards

### Required Frontmatter

Every skill must have:

```yaml
---
name: skill-name
description: When to use this skill - be specific about triggers
---
```

### Required Sections

Skills should include as appropriate:

1. **Overview** - What this skill does and core principle
2. **When to Use** - Specific triggers for invoking this skill
3. **The Protocol/Process** - Step-by-step instructions
4. **Checklist** - Verification items
5. **Integration** - What skills this calls or is called by

### Pattern Consistency

Match existing patterns in this repository:

- Use tables for structured information
- Use code blocks for commands and examples
- Use blockquotes for announcements
- Keep language direct and imperative
- No fluff, no filler

---

## Repository-Specific Rules

### Directory Structure

```
skills/
  skill-name/
    SKILL.md        # The skill definition
templates/          # Shared templates
hooks/              # Session hooks
```

Skills must be directly under `skills/` - not nested in category subdirectories.

### Skill Naming

- Use kebab-case: `skill-name`
- Be descriptive: `research-after-failure` not `research`
- Match the `name` field in frontmatter exactly to directory name

### Testing Skills

Before committing a new or modified skill:

1. Verify the skill loads (check for syntax errors in frontmatter)
2. Read through as if you were following it - does it make sense?
3. Check all referenced skills exist
4. Verify all links work

---

## Recovery From Failure

### If You Realize You Cut Corners

1. **Stop immediately** - Do not continue
2. **Acknowledge the failure** - Be explicit about what was skipped
3. **Revert if necessary** - Undo incomplete or unverified work
4. **Restart properly** - Begin again with full research and methodology
5. **Do not apologize repeatedly** - Fix it and move on

### If Research Reveals Your Approach Was Wrong

1. **Stop the current approach** - Do not try to salvage it
2. **Document what you learned** - Why was it wrong?
3. **Research the correct approach** - Use the research protocol
4. **Start fresh** - Do not patch incorrect work

---

## Quick Reference

### Before ANY Task

- [ ] Research current Claude Code documentation
- [ ] Research existing patterns in this repository
- [ ] Research current best practices (web search)
- [ ] Announce your research findings

### Before Modifying a Skill

- [ ] Read the entire skill
- [ ] Summarize its purpose
- [ ] Identify integration points
- [ ] Understand patterns used

### Before Claiming Completion

- [ ] Skill loads correctly
- [ ] Follows established patterns
- [ ] Documentation complete
- [ ] Research backing documented
- [ ] Integration verified
- [ ] Provide explicit verification statement

### When Uncertain

- [ ] Stop
- [ ] Research
- [ ] If still uncertain, ask
- [ ] Never guess

---

## The Bottom Line

You are working on a repository that defines how Claude should work. The standards here must be higher than anywhere else.

**Research first. Work slowly. Verify everything. No shortcuts.**

If this feels tedious, good. Tedium prevents errors. Speed creates them.
