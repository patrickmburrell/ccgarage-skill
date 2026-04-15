#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="${1:-}"
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"

if [[ ! -f "$INSTALLED_FILE" ]]; then
  echo "No installed plugins"
  exit 1
fi

# Check file format version
FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

if [[ "$FORMAT_VERSION" -eq 1 ]]; then
  echo "Error: installed_plugins.json is v1 format, please upgrade to v2"
  exit 1
fi

# Build list of plugins to upgrade with their sources and current SHAs
declare -A PLUGIN_MAP  # key -> "name|source|installed_sha"
declare -A SOURCE_HEAD_SHA  # source -> HEAD sha

# Parse v2 format: iterate over object keys like "plugin@source"
while IFS='|' read -r KEY NAME SOURCE INSTALLED_SHA; do
  PLUGIN_MAP["$KEY"]="$NAME|$SOURCE|$INSTALLED_SHA"

  # Get HEAD SHA for this source (cache to avoid repeated git calls)
  if [[ -z "${SOURCE_HEAD_SHA[$SOURCE]:-}" ]]; then
    MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"
    if [[ ! -d "$MARKETPLACE_DIR/.git" ]]; then
      echo "⚠ Marketplace not found: $SOURCE (expected at $MARKETPLACE_DIR)"
      continue
    fi
    SOURCE_HEAD_SHA["$SOURCE"]=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
  fi
done < <(jq -r '.plugins | to_entries[] | "\(.key)|\(.key | split("@")[0])|\(.key | split("@")[1])|\(.value[0].gitCommitSha)"' "$INSTALLED_FILE")

# Filter to just outdated plugins
declare -a TO_UPGRADE
if [[ -n "$PLUGIN_NAME" ]]; then
  # Single plugin - find all matching keys (could be multiple sources)
  FOUND=false
  for KEY in "${!PLUGIN_MAP[@]}"; do
    IFS='|' read -r NAME SOURCE INSTALLED_SHA <<< "${PLUGIN_MAP[$KEY]}"
    if [[ "$NAME" == "$PLUGIN_NAME" ]]; then
      FOUND=true
      HEAD_SHA="${SOURCE_HEAD_SHA[$SOURCE]}"
      if [[ "$INSTALLED_SHA" == "$HEAD_SHA" ]]; then
        echo "✓ $PLUGIN_NAME@$SOURCE already at latest (${HEAD_SHA:0:7})"
      else
        TO_UPGRADE+=("$KEY")
      fi
    fi
  done
  if [[ "$FOUND" == false ]]; then
    echo "Error: Plugin '$PLUGIN_NAME' not installed"
    exit 1
  fi
  if [[ ${#TO_UPGRADE[@]} -eq 0 ]]; then
    exit 0
  fi
else
  # All outdated plugins
  for KEY in "${!PLUGIN_MAP[@]}"; do
    IFS='|' read -r NAME SOURCE INSTALLED_SHA <<< "${PLUGIN_MAP[$KEY]}"
    HEAD_SHA="${SOURCE_HEAD_SHA[$SOURCE]}"
    if [[ -n "$HEAD_SHA" && "$INSTALLED_SHA" != "$HEAD_SHA" ]]; then
      TO_UPGRADE+=("$KEY")
    fi
  done
  if [[ ${#TO_UPGRADE[@]} -eq 0 ]]; then
    echo "✓ All plugins already up to date"
    exit 0
  fi
fi

# Upgrade each plugin
for KEY in "${TO_UPGRADE[@]}"; do
  IFS='|' read -r NAME SOURCE INSTALLED_SHA <<< "${PLUGIN_MAP[$KEY]}"
  HEAD_SHA="${SOURCE_HEAD_SHA[$SOURCE]}"
  MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"

  echo "Upgrading $NAME@$SOURCE..."

  # Get install path and version from current record
  INSTALL_PATH=$(jq -r --arg key "$KEY" '.plugins[$key][0].installPath' "$INSTALLED_FILE")
  VERSION=$(jq -r --arg key "$KEY" '.plugins[$key][0].version // "unknown"' "$INSTALLED_FILE")

  # Re-install from marketplace at HEAD
  PLUGIN_SRC="$MARKETPLACE_DIR/plugins/$NAME"

  if [[ ! -d "$PLUGIN_SRC" ]]; then
    echo "  ⚠ Plugin source not found in marketplace, skipping"
    continue
  fi

  # Copy to existing install path
  rm -rf "$INSTALL_PATH"
  mkdir -p "$(dirname "$INSTALL_PATH")"
  cp -R "$PLUGIN_SRC" "$INSTALL_PATH"

  # Update installed_plugins.json - update gitCommitSha and lastUpdated
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg key "$KEY" --arg sha "$HEAD_SHA" --arg now "$NOW" \
    '.plugins[$key][0].gitCommitSha = $sha |
     .plugins[$key][0].lastUpdated = $now' \
    "$INSTALLED_FILE" > "$INSTALLED_FILE.tmp"
  mv "$INSTALLED_FILE.tmp" "$INSTALLED_FILE"

  echo "  ✓ $NAME updated ${INSTALLED_SHA:0:7} → ${HEAD_SHA:0:7}"
done
