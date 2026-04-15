---
name: ccgarage
description: Claude Code maintenance — manage plugins, skills, memory, and configuration
---

# Claude Code Maintenance (`/ccgarage`)

Unified maintenance workflow for Claude Code ecosystem. Verbs mirror homebrew UX.

## Usage

`/ccgarage <verb> [args]`

If no verb given (or verb is `help`), this usage message displays.

## Available Verbs

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

---

## Implementation

**For Claude:** When user provides `/ccgarage <verb> [args]`:

1. Extract verb from args (first word, defaults to "help")
2. If verb is "help" or unknown, show usage above
3. Otherwise, run: `bash ~/.claude/skills/ccgarage/bin/<verb>.sh [args]`
4. Present output to user

**Example:**
- User: `/ccgarage tuneup`
- Claude runs: `bash ~/.claude/skills/ccgarage/bin/tuneup.sh`
- Claude presents the output

## Dispatch: Direct Script Execution

**For Claude: Execute pre-extracted bash scripts directly instead of using subagents.**

When user invokes `/ccgarage <verb>`:

1. **Validate verb** - Check it's one of: update, outdated, upgrade, install, remove, list, info, doctor, cleanup, tuneup
2. **Run script** - Execute `~/.claude/skills/ccgarage/bin/<verb>.sh` using Bash tool
3. **Present output** - Show results to user
4. **For mutating verbs** (cleanup, install, remove, upgrade): Get user confirmation before executing changes

### Read-only verbs (run and present results)

`doctor`, `outdated`, `list`, `info`, `tuneup`, `update` — run the script and present formatted output directly.

### Mutating verbs (confirm before acting)

`cleanup`, `install`, `remove`, `upgrade` — if the command would modify state, confirm with user first.

### Sync Check (optional)

If a script is missing or throws an error, check if scripts need regeneration:

```bash
cd ~/.claude/skills/ccgarage && make sync
```

This extracts bash blocks from .md files to bin/*.sh scripts.

### Token Efficiency Gains

- **Old approach**: Subagent reads 4 .md files (400-500 lines of markdown per tuneup)
- **New approach**: Direct script execution (output only, ~50-100 lines)
- **Savings**: ~80% token reduction per invocation
- **No subagent overhead**: Faster execution, cleaner context
