# /ccgarage - Claude Code Maintenance Skill

Unified maintenance workflow for Claude Code ecosystem. Part of the "garage" family (ccgarage, gharage, svcgarage) - the place to inspect and tune up your tools.

## Installation

```bash
# Clone or copy to Claude Code skills directory
git clone https://github.com/patrickmburrell/ccgarage-skill.git ~/.claude/skills/ccgarage
```

## Usage

`/ccgarage <verb> [args]`

### Available Verbs

**Package Management**:
- `update` — Sync marketplace repo (git pull)
- `outdated` — Show plugins with available updates
- `upgrade [plugin]` — Update plugins to latest (all if no arg)
- `install <plugin|repo>` — Install from marketplace or GitHub (e.g., `obra/superpowers`)
- `remove <plugin>` — Uninstall plugin

**Inventory** (marketplace plugins + custom skills):
- `list [plugins|skills]` — Show everything installed
- `info <name>` — Details about plugin or skill

**Health** (full ecosystem):
- `doctor` — Diagnose health issues (read-only)
- `cleanup [--dry-run]` — Act on problems (tiered safety)

**Convenience**:
- `tuneup` — Chains update → doctor → outdated

See [SKILL.md](SKILL.md) for complete documentation.

## Features

- Package management with homebrew-style UX
- Inventory tracking for plugins and custom skills
- Health checks and automated cleanup
- Git-sourced plugin support (GitHub repos)
- v2 format support for installed_plugins.json
- Subagent dispatch pattern to keep context clean

## Architecture

Router pattern with verb dispatch. `SKILL.md` parses the verb and dispatches to sub-skill files (`update.md`, `doctor.md`, etc.). Uses Agent tool to spawn subagents that read and execute sub-skills, returning only results (not the skill contents) to keep conversation context lean.

## License

MIT
