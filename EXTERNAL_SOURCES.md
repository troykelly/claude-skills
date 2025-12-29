# External Source Attribution

This document tracks skills and agents sourced from external repositories.

## Source Repository

**Repository:** [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
**Description:** Anthropic-managed directory of high quality Claude Code Plugins
**License:** See source repository for license terms

## Synced Artifacts

The following artifacts are synced from the official repository. **Do not edit these files directly** - changes will be overwritten on next sync.

### Agents (from `pr-review-toolkit` plugin)

| Local Path | Source Path | Description |
|------------|-------------|-------------|
| `external/agents/silent-failure-hunter.md` | `plugins/pr-review-toolkit/agents/silent-failure-hunter.md` | Identifies silent failures and inadequate error handling |
| `external/agents/pr-test-analyzer.md` | `plugins/pr-review-toolkit/agents/pr-test-analyzer.md` | Reviews PR test coverage quality |
| `external/agents/type-design-analyzer.md` | `plugins/pr-review-toolkit/agents/type-design-analyzer.md` | Analyzes type design for invariants and encapsulation |
| `external/agents/code-simplifier.md` | `plugins/pr-review-toolkit/agents/code-simplifier.md` | Simplifies code while preserving functionality |
| `external/agents/comment-analyzer.md` | `plugins/pr-review-toolkit/agents/comment-analyzer.md` | Analyzes code comments for accuracy and maintainability |

### Agents (from `feature-dev` plugin)

| Local Path | Source Path | Description |
|------------|-------------|-------------|
| `external/agents/code-architect.md` | `plugins/feature-dev/agents/code-architect.md` | Designs feature architectures with implementation blueprints |
| `external/agents/code-explorer.md` | `plugins/feature-dev/agents/code-explorer.md` | Traces execution paths and maps architecture layers |

### Skills (from `plugin-dev` plugin)

| Local Path | Source Path | Description |
|------------|-------------|-------------|
| `external/skills/skill-development/` | `plugins/plugin-dev/skills/skill-development/` | Skill authoring best practices |
| `external/skills/hook-development/` | `plugins/plugin-dev/skills/hook-development/` | Hook creation and validation |
| `external/skills/agent-development/` | `plugins/plugin-dev/skills/agent-development/` | Agent authoring guidance |

## Why These Artifacts

### Complementing Issue-Driven Development

| External Artifact | Complements Our Skill | Purpose |
|-------------------|----------------------|---------|
| `silent-failure-hunter` | `comprehensive-review` | Catches error handling gaps our review might miss |
| `pr-test-analyzer` | `tdd-full-coverage` | Provides test coverage analysis during PR review |
| `type-design-analyzer` | `strict-typing` | Deep type design analysis beyond basic typing |
| `code-simplifier` | Post-implementation | Simplifies code after implementation complete |
| `comment-analyzer` | `inline-documentation` | Validates comment accuracy against code |
| `code-architect` | `pre-work-research` | Provides architectural design before coding |
| `code-explorer` | `session-start` | Deep codebase exploration for understanding |

### Plugin Development Helpers

The `plugin-dev` skills help us maintain and improve this plugin itself:
- `skill-development` - For writing new skills
- `hook-development` - For creating/modifying hooks
- `agent-development` - For creating new agents

## Sync Process

Run the sync script to update external sources:

```bash
./scripts/sync-external-sources.sh
```

The script:
1. Fetches latest from `anthropics/claude-plugins-official`
2. Copies specified artifacts to `external/`
3. Preserves directory structure
4. Logs sync timestamp and commit hash

## Modification Policy

| Directory | Editable? | Notes |
|-----------|-----------|-------|
| `external/` | NO | Overwritten on sync - make changes upstream |
| `agents/` | YES | Our custom agents |
| `skills/` | YES | Our custom skills |

To modify an external artifact:
1. Fork the upstream repository
2. Make changes there
3. Submit PR to upstream
4. Once merged, sync will bring changes here

## Version Tracking

Sync metadata is stored in `external/.sync-metadata.json`:

```json
{
  "source_repo": "anthropics/claude-plugins-official",
  "last_sync": "2025-12-29T10:30:00Z",
  "commit_hash": "abc123...",
  "synced_paths": [...]
}
```

## Integration with Plugin

The `plugin.json` includes external agents:

```json
{
  "agents": [
    "./agents/code-reviewer.md",
    "./agents/security-reviewer.md",
    "./external/agents/silent-failure-hunter.md",
    "./external/agents/pr-test-analyzer.md",
    ...
  ]
}
```

External skills are discovered automatically from `external/skills/`.
