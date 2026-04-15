#!/usr/bin/env bash
set -euo pipefail

FILTER="${1:-all}"  # all, plugins, or skills

INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
SKILLS_DIR="$HOME/.claude/skills"

show_plugins() {
  if [[ ! -f "$INSTALLED_FILE" ]]; then
    echo "Marketplace Plugins (0 installed)"
    return
  fi

  # Check file format version
  FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

  if [[ "$FORMAT_VERSION" -eq 1 ]]; then
    echo "Error: installed_plugins.json is v1 format, please upgrade to v2"
    return
  fi

  COUNT=$(jq -r '.plugins | to_entries | length' "$INSTALLED_FILE")
  echo "Marketplace Plugins ($COUNT installed)"

  if (( COUNT == 0 )); then
    return
  fi

  # Parse v2 format
  jq -r '.plugins | to_entries[] |
    "\(.key | split("@")[0])|\(.key | split("@")[1])|\(.value[0].gitCommitSha // "unknown")|\(.value[0].lastUpdated // .value[0].installedAt // "unknown")"' \
    "$INSTALLED_FILE" | \
  while IFS='|' read -r NAME SOURCE SHA UPDATED_AT; do
    # Format date
    if [[ "$UPDATED_AT" != "unknown" ]]; then
      DATE=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${UPDATED_AT%Z}" +"%Y-%m-%d" 2>/dev/null || echo "$UPDATED_AT")
    else
      DATE="unknown"
    fi

    printf "  %-30s %-12s updated %s\n" "$NAME@$SOURCE" "${SHA:0:7}" "$DATE"
  done
}

show_skills() {
  if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "Custom Skills (0 installed)"
    return
  fi

  # Count skills (directories with SKILL.md)
  COUNT=0
  for SKILL_PATH in "$SKILLS_DIR"/*; do
    if [[ -d "$SKILL_PATH" && -f "$SKILL_PATH/SKILL.md" ]]; then
      ((COUNT++))
    fi
  done

  echo "Custom Skills ($COUNT installed)"

  if (( COUNT == 0 )); then
    return
  fi

  for SKILL_PATH in "$SKILLS_DIR"/*; do
    if [[ -d "$SKILL_PATH" && -f "$SKILL_PATH/SKILL.md" ]]; then
      SKILL_NAME=$(basename "$SKILL_PATH")
      # Get last modified date
      if [[ "$(uname)" == "Darwin" ]]; then
        MOD_DATE=$(stat -f "%Sm" -t "%Y-%m-%d" "$SKILL_PATH/SKILL.md")
      else
        MOD_DATE=$(stat -c "%y" "$SKILL_PATH/SKILL.md" | cut -d' ' -f1)
      fi
      printf "  %-20s modified %s\n" "$SKILL_NAME" "$MOD_DATE"
    fi
  done
}

case "$FILTER" in
  plugins)
    show_plugins
    ;;
  skills)
    show_skills
    ;;
  all|*)
    show_plugins
    echo ""
    show_skills
    ;;
esac
