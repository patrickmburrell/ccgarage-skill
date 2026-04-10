---
name: cc
description: Claude Code maintenance — manage plugins, skills, memory, and configuration
---

# Claude Code Maintenance (`/cc`)

Unified maintenance workflow for Claude Code ecosystem. Verbs mirror homebrew UX.

## Usage

`/cc <verb> [args]`

If no verb given (or verb is `help`), this usage message displays.

## Available Verbs

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

---

## Implementation

Parse verb from args, dispatch to sub-skill file:

```bash
# Extract verb from args (first word, or "help" if empty)
VERB="${1:-help}"

case "$VERB" in
  update)   SKILL_FILE="update.md" ;;
  outdated) SKILL_FILE="outdated.md" ;;
  upgrade)  SKILL_FILE="upgrade.md" ;;
  install)  SKILL_FILE="install.md" ;;
  remove)   SKILL_FILE="remove.md" ;;
  list)     SKILL_FILE="list.md" ;;
  info)     SKILL_FILE="info.md" ;;
  doctor)   SKILL_FILE="doctor.md" ;;
  cleanup)  SKILL_FILE="cleanup.md" ;;
  tuneup)   SKILL_FILE="tuneup.md" ;;
  help|*)
    # Show usage (the content above) and exit
    echo "See SKILL.md for usage"
    exit 0
    ;;
esac

# Hand off to sub-skill with remaining args
shift  # remove verb from args
exec invoke-skill "cc:$SKILL_FILE" "$@"
```

## Dispatch: Subagent Pattern

**When dispatching to a sub-skill, use the Agent tool** to spawn a subagent that:

1. Reads `~/.claude/skills/cc/<verb>.md`
2. Executes the bash logic, adapting as needed for actual file formats on disk
3. Returns **only the formatted diagnostic/action output** — not the skill file contents

This keeps the sub-skill markdown and bash code out of the main conversation context,
which would otherwise overwhelm the actual results with noise.

### Read-only verbs (subagent runs autonomously)

`doctor`, `outdated`, `list`, `info`, `tuneup`, `update` — subagent reads the skill,
runs checks, returns formatted results.

### Mutating verbs (two-step: diagnose then confirm)

`cleanup`, `install`, `remove`, `upgrade` — subagent reads the skill, runs the
**diagnostic/validation** portion, and returns findings. The main conversation then
presents findings to the user, gets confirmation, and executes the confirmed actions
(directly or via another subagent).

### Why subagents instead of direct execution

- **Problem:** Reading `.md` files dumps hundreds of lines of markdown + embedded bash
  into the conversation, overwhelming the actual 10-line diagnostic output.
- **Alternative considered:** Don't read the file, execute from memory. Rejected because
  Claude may hallucinate skill details across sessions as context and memory change.
- **Alternative considered:** Extract bash to `.sh` scripts. Rejected because it loses
  Claude's ability to adapt logic to actual file formats (e.g., installed_plugins.json
  v1 vs v2 schema differences) and doubles the maintenance burden.
- **Chosen approach:** Subagent reads and executes, returning only results. Preserves
  adaptability, eliminates noise, re-reads the real file every time.
- **Tradeoff:** Slightly slower (subagent spin-up). Acceptable for maintenance commands
  that run infrequently.
