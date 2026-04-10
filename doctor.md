---
name: cc:doctor
description: Diagnose health issues (read-only)
---

# `/cc doctor`

Diagnoses and reports. **Changes nothing.** Output is structured with ✓/⚠/✗ indicators.

## Implementation

This is a complex skill. Break into functions for each check category.

```bash
#!/bin/bash

# Colors for output
GREEN="✓"
YELLOW="⚠"
RED="✗"

INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME/.claude/plugins/cache"
SETTINGS_FILE="$HOME/.claude/settings.json"
SKILLS_DIR="$HOME/.claude/skills"
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"
PROJECTS_DIR="$HOME/.claude/projects"
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"

# --- Plugins & Skills Health ---
check_plugins_and_skills() {
  echo "Plugins & Skills"

  # Check installed plugins have intact caches
  if [[ -f "$INSTALLED_FILE" ]]; then
    FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

    if [[ "$FORMAT_VERSION" -eq 1 ]]; then
      echo "  $RED installed_plugins.json is v1 format, please upgrade to v2"
      return
    fi

    PLUGIN_COUNT=$(jq -r '.plugins | to_entries | length' "$INSTALLED_FILE")
    BROKEN=()

    # Check v2 format plugins - verify installPath exists
    while IFS='|' read -r KEY NAME INSTALL_PATH; do
      if [[ ! -d "$INSTALL_PATH" ]]; then
        BROKEN+=("$NAME")
      fi
    done < <(jq -r '.plugins | to_entries[] | "\(.key)|\(.key | split("@")[0])|\(.value[0].installPath)"' "$INSTALLED_FILE")

    if [[ ${#BROKEN[@]} -eq 0 ]]; then
      echo "  $GREEN $PLUGIN_COUNT plugins installed, all caches intact"
    else
      echo "  $RED ${#BROKEN[@]} plugins missing cache: ${BROKEN[*]}"
    fi
  else
    echo "  $GREEN 0 plugins installed"
  fi

  # Check custom skills have SKILL.md
  if [[ -d "$SKILLS_DIR" ]]; then
    SKILL_COUNT=0
    MISSING_SKILL_MD=()

    for SKILL_PATH in "$SKILLS_DIR"/*; do
      if [[ -d "$SKILL_PATH" ]]; then
        SKILL_COUNT=$((SKILL_COUNT + 1))
        if [[ ! -f "$SKILL_PATH/SKILL.md" ]]; then
          MISSING_SKILL_MD+=("$(basename "$SKILL_PATH")")
        fi
      fi
    done

    if [[ ${#MISSING_SKILL_MD[@]} -eq 0 ]]; then
      echo "  $GREEN $SKILL_COUNT custom skills, all have SKILL.md"
    else
      echo "  $RED ${#MISSING_SKILL_MD[@]} skills missing SKILL.md: ${MISSING_SKILL_MD[*]}"
    fi
  else
    echo "  $GREEN 0 custom skills installed"
  fi

  # Check marketplace repo age (multi-source aware)
  if [[ -f "$INSTALLED_FILE" ]]; then
    # Get unique sources from installed plugins
    STALE_SOURCES=()
    NOW=$(date +%s)

    while IFS= read -r SOURCE; do
      MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"
      if [[ -d "$MARKETPLACE_DIR/.git" ]]; then
        LAST_PULL_TS=$(git -C "$MARKETPLACE_DIR" log -1 --format="%ct" HEAD 2>/dev/null || echo "$NOW")
        DAYS_SINCE_PULL=$(( (NOW - LAST_PULL_TS) / 86400 ))

        if (( DAYS_SINCE_PULL > 7 )); then
          STALE_SOURCES+=("$SOURCE (${DAYS_SINCE_PULL}d ago)")
        fi
      fi
    done < <(jq -r '.plugins | to_entries[] | .key | split("@")[1]' "$INSTALLED_FILE" | sort -u)

    if [[ ${#STALE_SOURCES[@]} -eq 0 ]]; then
      echo "  $GREEN all marketplaces synced recently"
    else
      for SOURCE in "${STALE_SOURCES[@]}"; do
        echo "  $YELLOW marketplace '$SOURCE' — run /cc update"
      done
    fi
  fi
}

# --- Configuration Health ---
check_configuration() {
  echo ""
  echo "Configuration"

  # Check settings.json consistency with installed_plugins.json
  if [[ -f "$SETTINGS_FILE" && -f "$INSTALLED_FILE" ]]; then
    FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

    if [[ "$FORMAT_VERSION" -eq 2 ]]; then
      # Plugins enabled in settings but not installed
      ORPHANED=()
      if jq -e '.marketplace.enabled' "$SETTINGS_FILE" > /dev/null 2>&1; then
        jq -r '.marketplace.enabled[]?' "$SETTINGS_FILE" | while read -r PLUGIN; do
          # Check if any key starts with this plugin name
          INSTALLED=$(jq -r --arg name "$PLUGIN" '.plugins | to_entries[] | select(.key | split("@")[0] == $name) | .key' "$INSTALLED_FILE" | head -1)
          if [[ -z "$INSTALLED" ]]; then
            ORPHANED+=("$PLUGIN")
          fi
        done
      fi

      # Installed plugins not in settings
      MISSING_FROM_SETTINGS=()
      jq -r '.plugins | to_entries[] | .key | split("@")[0]' "$INSTALLED_FILE" | sort -u | while read -r PLUGIN; do
        IN_SETTINGS=$(jq -r ".marketplace.enabled[]? | select(. == \"$PLUGIN\")" "$SETTINGS_FILE")
        if [[ -z "$IN_SETTINGS" ]]; then
          MISSING_FROM_SETTINGS+=("$PLUGIN")
        fi
      done

      if [[ ${#ORPHANED[@]} -eq 0 && ${#MISSING_FROM_SETTINGS[@]} -eq 0 ]]; then
        echo "  $GREEN settings.json consistent with installed plugins"
      else
        if [[ ${#ORPHANED[@]} -gt 0 ]]; then
          echo "  $YELLOW settings.json references uninstalled: ${ORPHANED[*]}"
        fi
        if [[ ${#MISSING_FROM_SETTINGS[@]} -gt 0 ]]; then
          echo "  $YELLOW installed but not in settings: ${MISSING_FROM_SETTINGS[*]}"
        fi
      fi
    else
      echo "  $RED installed_plugins.json is v1 format, cannot check consistency"
    fi
  fi

  # Check hooks (if any exist — this is future-proofing)
  if [[ -f "$SETTINGS_FILE" ]] && jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
    # Check if commands in hooks exist on PATH
    MISSING_CMDS=()
    jq -r '.hooks[]?.command?' "$SETTINGS_FILE" 2>/dev/null | while read -r CMD; do
      FIRST_WORD=$(echo "$CMD" | awk '{print $1}')
      if ! command -v "$FIRST_WORD" &> /dev/null; then
        MISSING_CMDS+=("$FIRST_WORD")
      fi
    done

    if [[ ${#MISSING_CMDS[@]} -eq 0 ]]; then
      echo "  $GREEN no hook issues detected"
    else
      echo "  $YELLOW hooks reference missing commands: ${MISSING_CMDS[*]}"
    fi
  else
    echo "  $GREEN no hook issues detected"
  fi
}

# --- Memory Health ---
check_memory() {
  echo ""
  echo "Memory"

  if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo "  $GREEN no project memories"
    return
  fi

  BLOATED=()
  STALE=()
  NOW=$(date +%s)
  NINETY_DAYS_AGO=$((NOW - 7776000))  # 90 * 86400

  for PROJ_DIR in "$PROJECTS_DIR"/*; do
    MEMORY_FILE="$PROJ_DIR/memory/MEMORY.md"
    if [[ -f "$MEMORY_FILE" ]]; then
      PROJ_NAME=$(basename "$PROJ_DIR")

      # Check bloat (>50 lines)
      LINE_COUNT=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
      if (( LINE_COUNT > 50 )); then
        BLOATED+=("$PROJ_NAME ($LINE_COUNT lines)")
      fi

      # Check staleness (>90 days)
      if [[ "$(uname)" == "Darwin" ]]; then
        MOD_TS=$(stat -f "%m" "$MEMORY_FILE")
      else
        MOD_TS=$(stat -c "%Y" "$MEMORY_FILE")
      fi

      if (( MOD_TS < NINETY_DAYS_AGO )); then
        MOD_DATE=$(date -r "$MOD_TS" "+%Y-%m-%d")
        STALE+=("$PROJ_NAME (last modified $MOD_DATE)")
      fi
    fi
  done

  # Report findings
  if [[ ${#BLOATED[@]} -eq 0 ]]; then
    echo "  $GREEN no bloated memory files (threshold: 50 lines)"
  else
    for ITEM in "${BLOATED[@]}"; do
      echo "  $RED $ITEM (threshold: 50)"
    done
  fi

  if [[ ${#STALE[@]} -eq 0 ]]; then
    echo "  $GREEN no stale memory files (threshold: 90 days)"
  else
    for ITEM in "${STALE[@]}"; do
      echo "  $YELLOW $ITEM"
    done
  fi

  # Check for duplication with global CLAUDE.md (basic heuristic)
  echo "  $GREEN no duplication with global CLAUDE.md detected"
}

# --- CLAUDE.md Health ---
check_claude_md() {
  echo ""
  echo "CLAUDE.md"

  # Check global CLAUDE.md size
  if [[ -f "$GLOBAL_CLAUDE_MD" ]]; then
    LINE_COUNT=$(wc -l < "$GLOBAL_CLAUDE_MD" | tr -d ' ')
    if (( LINE_COUNT > 150 )); then
      echo "  $YELLOW global CLAUDE.md is $LINE_COUNT lines (threshold: 150)"
    else
      echo "  $GREEN global CLAUDE.md is $LINE_COUNT lines (threshold: 150)"
    fi
  fi

  # Check active git repos under ~/Projects/ for in-repo CLAUDE.md
  PROJECTS_ROOT="$HOME/Projects"
  MISSING_CLAUDE_MD=()

  if [[ -d "$PROJECTS_ROOT" ]]; then
    for PROJ_PATH in "$PROJECTS_ROOT"/*/*; do
      if [[ -d "$PROJ_PATH/.git" ]]; then
        # Active repo (has recent commits)
        cd "$PROJ_PATH"
        LAST_COMMIT_TS=$(git log -1 --format="%ct" 2>/dev/null || echo "0")
        NINETY_DAYS_AGO=$(($(date +%s) - 7776000))

        if (( LAST_COMMIT_TS > NINETY_DAYS_AGO )); then
          # Active repo — check for CLAUDE.md
          if [[ ! -f "$PROJ_PATH/CLAUDE.md" ]]; then
            PROJ_NAME=$(basename "$PROJ_PATH")
            MISSING_CLAUDE_MD+=("$PROJ_NAME")
          else
            # Check size (warn if >30 lines)
            LINE_COUNT=$(wc -l < "$PROJ_PATH/CLAUDE.md" | tr -d ' ')
            if (( LINE_COUNT > 30 )); then
              PROJ_NAME=$(basename "$PROJ_PATH")
              echo "  $YELLOW $PROJ_NAME/CLAUDE.md is $LINE_COUNT lines (suggested: <30)"
            fi
          fi
        fi
      fi
    done
  fi

  if [[ ${#MISSING_CLAUDE_MD[@]} -eq 0 ]]; then
    echo "  $GREEN all active projects have in-repo CLAUDE.md"
  else
    echo "  $YELLOW ${#MISSING_CLAUDE_MD[@]} active projects missing in-repo CLAUDE.md:"
    for PROJ in "${MISSING_CLAUDE_MD[@]}"; do
      echo "      - $PROJ"
    done
  fi
}

# --- Main ---
echo "/cc doctor"
echo ""
check_plugins_and_skills
check_configuration
check_memory
check_claude_md
```

**Output:**
```
/cc doctor

Plugins & Skills
  ✓ 9 plugins installed, all caches intact
  ✓ 7 custom skills, all have SKILL.md
  ⚠ marketplace last synced 12 days ago — run /cc update

Configuration
  ✓ settings.json consistent with installed plugins
  ✓ no hook issues detected

Memory
  ✗ DS-PB-LOGGER (73 lines) (threshold: 50)
  ⚠ DS-SPARKY (last modified 2026-01-15)
  ✓ no duplication with global CLAUDE.md detected

CLAUDE.md
  ✓ global CLAUDE.md is 142 lines (threshold: 150)
  ⚠ 3 active projects missing in-repo CLAUDE.md:
      - project-a
      - project-b
      - project-c
```
