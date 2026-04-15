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
- `install <plugin|repo>` — Install from marketplace or GitHub (e.g., `user/repo`)
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

Router pattern with verb dispatch. `SKILL.md` parses the verb and executes pre-built shell scripts from `bin/` directory. Scripts are extracted from bash code blocks in verb `.md` files using `make sync`.

### Token Efficiency

- **Old approach**: Subagent reads .md files (400-500 lines of markdown per tuneup)
- **New approach**: Direct script execution (output only, ~50-100 lines)
- **Savings**: ~80% token reduction per invocation

### Maintenance

When updating verb `.md` files, regenerate scripts:

```bash
cd ~/.claude/skills/ccgarage
make sync
```

Or clean and regenerate:

```bash
make clean
make sync
```

## License

MIT
