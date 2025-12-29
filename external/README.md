# External Sources

This directory contains skills and agents synced from [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official).

**DO NOT EDIT FILES IN THIS DIRECTORY** - changes will be overwritten on the next sync.

## Updating

To sync the latest versions:

```bash
./scripts/sync-external-sources.sh
```

## Current Sources

### Agents (from pr-review-toolkit)

| Agent | Purpose |
|-------|---------|
| `silent-failure-hunter` | Identifies silent failures and inadequate error handling |
| `pr-test-analyzer` | Reviews PR test coverage quality |
| `type-design-analyzer` | Analyzes type design for invariants and encapsulation |
| `code-simplifier` | Simplifies code while preserving functionality |
| `comment-analyzer` | Analyzes code comments for accuracy |

### Agents (from feature-dev)

| Agent | Purpose |
|-------|---------|
| `code-architect` | Designs feature architectures with implementation blueprints |
| `code-explorer` | Traces execution paths and maps architecture layers |

### Skills (from plugin-dev)

| Skill | Purpose |
|-------|---------|
| `skill-development` | Skill authoring best practices |
| `hook-development` | Hook creation and validation |
| `agent-development` | Agent authoring guidance |

## Sync Metadata

See `.sync-metadata.json` for:
- Source repository
- Last sync timestamp
- Source commit hash
- List of synced paths

## Contributing

To modify these files:
1. Fork `anthropics/claude-plugins-official`
2. Make changes in your fork
3. Submit a PR upstream
4. Once merged, run sync to update here

See [EXTERNAL_SOURCES.md](../EXTERNAL_SOURCES.md) for full documentation.
