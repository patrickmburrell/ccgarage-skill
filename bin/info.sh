#!/usr/bin/env bash
set -euo pipefail

NAME="$1"

if [[ -z "$NAME" ]]; then
  echo "Error: Plugin or skill name required"
  echo "Usage: /cc info <name>"
  exit 1
fi

INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME/.claude/plugins/cache"
SKILLS_DIR="$HOME/.claude/skills"
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Check if it's a plugin (v2 format)
if [[ -f "$INSTALLED_FILE" ]]; then
  FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

  if [[ "$FORMAT_VERSION" -eq 2 ]]; then
    # Find all matching plugin keys (could be multiple sources)
    while IFS='|' read -r KEY PLUGIN_NAME SOURCE; do
      if [[ "$PLUGIN_NAME" == "$NAME" ]]; then
        echo "Marketplace Plugin: $PLUGIN_NAME@$SOURCE"
        echo ""

        # Extract fields from v2 format
        SHA=$(jq -r --arg key "$KEY" '.plugins[$key][0].gitCommitSha // "unknown"' "$INSTALLED_FILE")
        VERSION=$(jq -r --arg key "$KEY" '.plugins[$key][0].version // "unknown"' "$INSTALLED_FILE")
        INSTALLED_AT=$(jq -r --arg key "$KEY" '.plugins[$key][0].installedAt // "unknown"' "$INSTALLED_FILE")
        INSTALL_PATH=$(jq -r --arg key "$KEY" '.plugins[$key][0].installPath // "unknown"' "$INSTALLED_FILE")

        if [[ "$VERSION" != "unknown" ]]; then
          echo "Version:       $VERSION"
        fi
        echo "Git SHA:       ${SHA:0:7} (full: $SHA)"
        echo "Installed:     $INSTALLED_AT"

        # Check if enabled
        if [[ -f "$SETTINGS_FILE" ]]; then
          ENABLED=$(jq -r ".marketplace.enabled[]? | select(. == \"$PLUGIN_NAME\")" "$SETTINGS_FILE")
          if [[ -n "$ENABLED" ]]; then
            echo "Status:        enabled"
          else
            echo "Status:        disabled"
          fi
        fi

        echo "Install path:  $INSTALL_PATH"

        # Check for updates (source-aware)
        MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"
        if [[ -d "$MARKETPLACE_DIR/.git" ]]; then
          CURRENT_SHA=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD 2>/dev/null)
          if [[ "$SHA" != "$CURRENT_SHA" ]]; then
            echo ""
            echo "⚠ Update available: ${CURRENT_SHA:0:7}"
            echo "  Run: /cc upgrade $PLUGIN_NAME"
          else
            echo "✓ Up to date"
          fi
        fi

        exit 0
      fi
    done < <(jq -r '.plugins | to_entries[] | "\(.key)|\(.key | split("@")[0])|\(.key | split("@")[1])"' "$INSTALLED_FILE")
  fi
fi

# Check if it's a custom skill
SKILL_PATH="$SKILLS_DIR/$NAME"
if [[ -d "$SKILL_PATH" && -f "$SKILL_PATH/SKILL.md" ]]; then
  echo "Custom Skill: $NAME"
  echo ""

  # Extract description from frontmatter if present
  DESC=$(grep -A 1 "^description:" "$SKILL_PATH/SKILL.md" | tail -n 1 | sed 's/^[[:space:]]*//')
  if [[ -n "$DESC" ]]; then
    echo "Description:   $DESC"
  fi

  echo "Path:          $SKILL_PATH"

  # Last modified
  if [[ "$(uname)" == "Darwin" ]]; then
    MOD_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$SKILL_PATH/SKILL.md")
  else
    MOD_DATE=$(stat -c "%y" "$SKILL_PATH/SKILL.md" | cut -d'.' -f1)
  fi
  echo "Last modified: $MOD_DATE"

  # Check for evals
  if [[ -d "$SKILL_PATH/evals" ]]; then
    EVAL_COUNT=$(ls -1 "$SKILL_PATH/evals" | wc -l | tr -d ' ')
    echo "Has evals:     yes ($EVAL_COUNT)"
  else
    echo "Has evals:     no"
  fi

  # Check for reference docs
  if [[ -f "$SKILL_PATH/reference.md" ]] || [[ -f "$SKILL_PATH/README.md" ]]; then
    echo "Has reference: yes"
  else
    echo "Has reference: no"
  fi

  exit 0
fi

echo "Error: '$NAME' not found (checked plugins and custom skills)"
exit 1
