#!/usr/bin/env bash
set -euo pipefail

#!/bin/bash

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "=== DRY RUN MODE (no changes will be made) ==="
  echo ""
fi

INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME/.claude/plugins/cache"
SETTINGS_FILE="$HOME/.claude/settings.json"
PROJECTS_DIR="$HOME/.claude/projects"

# --- Auto (no confirmation needed) ---
auto_cleanup() {
  echo "Auto Cleanup (no confirmation needed)"
  echo ""

  # Prune orphaned plugin cache directories (v2 format aware)
  if [[ -d "$CACHE_DIR" && -f "$INSTALLED_FILE" ]]; then
    FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

    if [[ "$FORMAT_VERSION" -eq 2 ]]; then
      # Get all installPaths from v2 format
      VALID_PATHS=()
      while IFS= read -r PATH; do
        VALID_PATHS+=("$PATH")
      done < <(jq -r '.plugins | to_entries[] | .value[0].installPath' "$INSTALLED_FILE")

      # Find directories in cache that aren't in valid paths
      ORPHANED=()
      # Check all source directories under cache
      for SOURCE_DIR in "$CACHE_DIR"/*; do
        if [[ -d "$SOURCE_DIR" ]]; then
          for PLUGIN_DIR in "$SOURCE_DIR"/*; do
            if [[ -d "$PLUGIN_DIR" ]]; then
              # Check if this path is in the valid list
              IS_VALID=false
              for VALID_PATH in "${VALID_PATHS[@]}"; do
                if [[ "$PLUGIN_DIR" == "$VALID_PATH"* ]]; then
                  IS_VALID=true
                  break
                fi
              done
              if [[ "$IS_VALID" == false ]]; then
                ORPHANED+=("$PLUGIN_DIR")
              fi
            fi
          done
        fi
      done

      if [[ ${#ORPHANED[@]} -gt 0 ]]; then
        for PATH in "${ORPHANED[@]}"; do
          echo "  Removing orphaned cache: $PATH"
          if [[ "$DRY_RUN" == false ]]; then
            rm -rf "$PATH"
          fi
        done
      else
        echo "  ✓ No orphaned caches found"
      fi
    else
      echo "  ⚠ installed_plugins.json is v1 format, skipping cache cleanup"
    fi
  fi

  # Remove empty/broken data directories
  DATA_DIR="$HOME/.claude/plugins/data"
  if [[ -d "$DATA_DIR" ]]; then
    EMPTY_DIRS=()
    for DIR in "$DATA_DIR"/*; do
      if [[ -d "$DIR" && -z "$(ls -A "$DIR")" ]]; then
        EMPTY_DIRS+=("$(basename "$DIR")")
      fi
    done

    if [[ ${#EMPTY_DIRS[@]} -gt 0 ]]; then
      for DIR in "${EMPTY_DIRS[@]}"; do
        echo "  Removing empty data dir: $DIR"
        if [[ "$DRY_RUN" == false ]]; then
          rmdir "$DATA_DIR/$DIR"
        fi
      done
    else
      echo "  ✓ No empty data directories"
    fi
  fi
}

# --- Confirm before acting ---
interactive_cleanup() {
  echo ""
  echo "Interactive Cleanup (confirmation required)"
  echo ""

  # Trim bloated memory files
  if [[ -d "$PROJECTS_DIR" ]]; then
    for PROJ_DIR in "$PROJECTS_DIR"/*; do
      MEMORY_FILE="$PROJ_DIR/memory/MEMORY.md"
      if [[ -f "$MEMORY_FILE" ]]; then
        LINE_COUNT=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
        if (( LINE_COUNT > 50 )); then
          PROJ_NAME=$(basename "$PROJ_DIR")
          echo "Memory file $PROJ_NAME is $LINE_COUNT lines (threshold: 50)"

          if [[ "$DRY_RUN" == false ]]; then
            read -p "  Open for review? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
              echo "  Opening $MEMORY_FILE in editor..."
              echo "  After review, manually trim and save"
              ${EDITOR:-nano} "$MEMORY_FILE"
            fi
          else
            echo "  [dry-run] Would prompt to open for review"
          fi
        fi
      fi
    done
  fi

  # Delete stale memory files
  NOW=$(date +%s)
  NINETY_DAYS_AGO=$((NOW - 7776000))

  if [[ -d "$PROJECTS_DIR" ]]; then
    for PROJ_DIR in "$PROJECTS_DIR"/*; do
      MEMORY_FILE="$PROJ_DIR/memory/MEMORY.md"
      if [[ -f "$MEMORY_FILE" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
          MOD_TS=$(stat -f "%m" "$MEMORY_FILE")
        else
          MOD_TS=$(stat -c "%Y" "$MEMORY_FILE")
        fi

        if (( MOD_TS < NINETY_DAYS_AGO )); then
          PROJ_NAME=$(basename "$PROJ_DIR")
          MOD_DATE=$(date -r "$MOD_TS" "+%Y-%m-%d")

          echo "Memory file $PROJ_NAME last modified $MOD_DATE (>90 days)"

          if [[ "$DRY_RUN" == false ]]; then
            read -p "  Delete? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
              rm "$MEMORY_FILE"
              rmdir "$PROJ_DIR/memory" 2>/dev/null
              echo "  ✓ Deleted"
            fi
          else
            echo "  [dry-run] Would prompt to delete"
          fi
        fi
      fi
    done
  fi

  # Remove plugins from settings.json that aren't in installed_plugins.json (v2 aware)
  if [[ -f "$SETTINGS_FILE" && -f "$INSTALLED_FILE" ]]; then
    FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

    if [[ "$FORMAT_VERSION" -eq 2 ]]; then
      ORPHANED=()
      if jq -e '.marketplace.enabled' "$SETTINGS_FILE" > /dev/null 2>&1; then
        while read -r PLUGIN; do
          # Check if any key starts with this plugin name (v2 format)
          INSTALLED=$(jq -r --arg name "$PLUGIN" '.plugins | to_entries[] | select(.key | split("@")[0] == $name) | .key' "$INSTALLED_FILE" | head -1)
          if [[ -z "$INSTALLED" ]]; then
            ORPHANED+=("$PLUGIN")
          fi
        done < <(jq -r '.marketplace.enabled[]?' "$SETTINGS_FILE")
      fi

      if [[ ${#ORPHANED[@]} -gt 0 ]]; then
        echo "Settings.json references ${#ORPHANED[@]} uninstalled plugins: ${ORPHANED[*]}"

        if [[ "$DRY_RUN" == false ]]; then
          read -p "  Remove from settings? (y/N) " -n 1 -r
          echo
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            for PLUGIN in "${ORPHANED[@]}"; do
              jq --arg name "$PLUGIN" \
                '.marketplace.enabled = [.marketplace.enabled[]? | select(. != $name)]' \
                "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
              mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            done
            echo "  ✓ Removed ${#ORPHANED[@]} entries from settings.json"
          fi
        else
          echo "  [dry-run] Would prompt to remove"
        fi
      fi
    else
      echo "  ⚠ installed_plugins.json is v1 format, skipping settings cleanup"
    fi
  fi
}

# --- Main ---
auto_cleanup
interactive_cleanup

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "=== DRY RUN COMPLETE (no changes made) ==="
fi
