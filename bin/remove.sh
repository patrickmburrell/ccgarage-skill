#!/usr/bin/env bash
set -euo pipefail

/cc remove superpowers                              # Remove all installations
/cc remove superpowers@claude-plugins-official      # Remove specific source
```
```bash
INPUT="$1"

if [[ -z "$INPUT" ]]; then
  echo "Error: Plugin name required"
  echo "Usage: /cc remove <plugin-name[@source]>"
  echo ""
  echo "Examples:"
  echo "  /cc remove superpowers                          # all installations"
  echo "  /cc remove superpowers@claude-plugins-official  # specific source"
  exit 1
fi

INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME/.claude/plugins/cache"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Parse input - could be "plugin" or "plugin@source"
if [[ "$INPUT" =~ @ ]]; then
  # Specific key requested
  PLUGIN_NAME=$(echo "$INPUT" | cut -d'@' -f1)
  SPECIFIED_SOURCE=$(echo "$INPUT" | cut -d'@' -f2)
  SPECIFIC_KEY="$INPUT"
else
  # Just plugin name - match all sources
  PLUGIN_NAME="$INPUT"
  SPECIFIED_SOURCE=""
  SPECIFIC_KEY=""
fi

CUSTOM_SKILL_PATH="$HOME/.claude/skills/$PLUGIN_NAME"

# Check if it's a custom skill, not a plugin
if [[ -d "$CUSTOM_SKILL_PATH" ]]; then
  echo "Error: '$PLUGIN_NAME' is a custom skill, not a marketplace plugin"
  echo "Custom skills must be removed manually from ~/.claude/skills/"
  exit 1
fi

# Check if installed
if [[ ! -f "$INSTALLED_FILE" ]]; then
  echo "Error: Plugin '$PLUGIN_NAME' not installed"
  exit 1
fi

FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

if [[ "$FORMAT_VERSION" -eq 1 ]]; then
  echo "Error: installed_plugins.json is v1 format, please upgrade to v2"
  exit 1
fi

# Find matching plugin keys (v2 format)
MATCHING_KEYS=()
if [[ -n "$SPECIFIC_KEY" ]]; then
  # Exact key match
  KEY_EXISTS=$(jq -r --arg key "$SPECIFIC_KEY" '.plugins[$key] // empty' "$INSTALLED_FILE")
  if [[ -n "$KEY_EXISTS" ]]; then
    MATCHING_KEYS+=("$SPECIFIC_KEY")
  fi
else
  # Match all keys with this plugin name
  while IFS= read -r KEY; do
    MATCHING_KEYS+=("$KEY")
  done < <(jq -r --arg name "$PLUGIN_NAME" '.plugins | to_entries[] | select(.key | split("@")[0] == $name) | .key' "$INSTALLED_FILE")
fi

if [[ ${#MATCHING_KEYS[@]} -eq 0 ]]; then
  if [[ -n "$SPECIFIC_KEY" ]]; then
    echo "Error: Plugin '$SPECIFIC_KEY' not installed"
  else
    echo "Error: Plugin '$PLUGIN_NAME' not installed"
  fi
  exit 1
fi

# Get install paths for cache cleanup
INSTALL_PATHS=()
for KEY in "${MATCHING_KEYS[@]}"; do
  INSTALL_PATH=$(jq -r --arg key "$KEY" '.plugins[$key][0].installPath // ""' "$INSTALLED_FILE")
  if [[ -n "$INSTALL_PATH" ]]; then
    INSTALL_PATHS+=("$INSTALL_PATH")
  fi
done

# Confirm before removing
if [[ ${#MATCHING_KEYS[@]} -eq 1 ]]; then
  echo "Remove plugin '${MATCHING_KEYS[0]}'?"
else
  echo "Remove ${#MATCHING_KEYS[@]} installations of '$PLUGIN_NAME'?"
  for KEY in "${MATCHING_KEYS[@]}"; do
    echo "  - $KEY"
  done
fi
read -p "This will disable and remove from installed list. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Removal cancelled"
  exit 0
fi

# Remove from installed_plugins.json (v2 format - delete keys)
TMP_JSON="$INSTALLED_FILE"
for KEY in "${MATCHING_KEYS[@]}"; do
  TMP_JSON=$(jq --arg key "$KEY" 'del(.plugins[$key])' "$INSTALLED_FILE")
  echo "$TMP_JSON" > "$INSTALLED_FILE"
done

# Remove from settings.json enabled list (only if no installations remain)
if [[ -f "$SETTINGS_FILE" ]]; then
  # Check if any installations of this plugin remain
  REMAINING=$(jq -r --arg name "$PLUGIN_NAME" '.plugins | to_entries[] | select(.key | split("@")[0] == $name) | .key' "$INSTALLED_FILE" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$REMAINING" -eq 0 ]]; then
    # No installations left - remove from settings
    jq --arg name "$PLUGIN_NAME" \
      '.marketplace.enabled = [.marketplace.enabled[]? | select(. != $name)]' \
      "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  fi
fi

# Ask about cleaning cached files
if [[ ${#INSTALL_PATHS[@]} -gt 0 ]]; then
  read -p "Also remove cached files? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    for INSTALL_PATH in "${INSTALL_PATHS[@]}"; do
      rm -rf "$INSTALL_PATH"
    done
    echo "✓ Removed $PLUGIN_NAME and cleaned cache"
  else
    echo "✓ Removed $PLUGIN_NAME (cache preserved)"
  fi
else
  echo "✓ Removed $PLUGIN_NAME"
fi
