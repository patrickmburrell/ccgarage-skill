---
name: cc:outdated
description: Check which installed plugins have updates available
---

# `/cc outdated`

Checks git history to see if specific plugin directories have updates in marketplace since installation.

## Implementation

```bash
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"

if [[ ! -f "$INSTALLED_FILE" ]]; then
  echo "No installed plugins"
  exit 0
fi

# Check file format version
FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

if [[ "$FORMAT_VERSION" -eq 1 ]]; then
  echo "Error: installed_plugins.json is v1 format, please upgrade to v2"
  exit 1
fi

NOW=$(date +%s)

# Check marketplace staleness and warn
declare -A SOURCE_STALE
while IFS= read -r SOURCE; do
  MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"

  if [[ ! -d "$MARKETPLACE_DIR/.git" ]]; then
    echo "⚠ Marketplace not found: $SOURCE"
    continue
  fi

  # Check if marketplace is stale (>7 days since last pull)
  LAST_PULL=$(git -C "$MARKETPLACE_DIR" log -1 --format="%ar" HEAD 2>/dev/null || echo "unknown")
  LAST_PULL_TS=$(git -C "$MARKETPLACE_DIR" log -1 --format="%ct" HEAD 2>/dev/null || echo "$NOW")
  DAYS_SINCE_PULL=$(( (NOW - LAST_PULL_TS) / 86400 ))

  if (( DAYS_SINCE_PULL > 7 )); then
    echo "⚠ Marketplace '$SOURCE' last synced $LAST_PULL — run /cc update first"
    SOURCE_STALE["$SOURCE"]=1
  fi
done < <(jq -r '.plugins | to_entries[] | .key | split("@")[1]' "$INSTALLED_FILE" | sort -u)

if [[ ${#SOURCE_STALE[@]} -gt 0 ]]; then
  echo ""
fi

# Check each plugin by examining if plugin directory changed in marketplace
OUTDATED_COUNT=0
jq -r '.plugins | to_entries[] | "\(.key)|\(.value[0].version // "unknown")|\(.value[0].installedAt // "unknown")|\(.value[0].gitCommitSha // "unknown")"' "$INSTALLED_FILE" | \
while IFS='|' read -r PLUGIN_KEY CURRENT_VERSION INSTALLED_AT INSTALLED_SHA; do
  NAME=$(echo "$PLUGIN_KEY" | cut -d'@' -f1)
  SOURCE=$(echo "$PLUGIN_KEY" | cut -d'@' -f2)
  
  MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"
  PLUGIN_DIR="plugins/$NAME"
  
  if [[ ! -d "$MARKETPLACE_DIR/.git" ]]; then
    continue  # Skip if marketplace not found
  fi
  
  if [[ "$INSTALLED_SHA" == "unknown" ]]; then
    echo "⚠ $PLUGIN_KEY: no install SHA recorded"
    continue
  fi
  
  # Check if plugin directory has changes since installed SHA
  HEAD_SHA=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD 2>/dev/null)
  
  if [[ "$INSTALLED_SHA" == "$HEAD_SHA" ]]; then
    # Installed from current HEAD - definitely up to date
    continue
  fi
  
  # Check if THIS SPECIFIC PLUGIN changed between installed SHA and HEAD
  CHANGES=$(git -C "$MARKETPLACE_DIR" log --oneline "$INSTALLED_SHA..$HEAD_SHA" -- "$PLUGIN_DIR" 2>/dev/null | wc -l)
  
  if [[ "$CHANGES" -gt 0 ]]; then
    # Plugin directory has changes
    if [[ "$INSTALLED_AT" != "unknown" ]]; then
      INSTALLED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${INSTALLED_AT%Z}" +%s 2>/dev/null || echo "$NOW")
      DAYS_OLD=$(( (NOW - INSTALLED_TS) / 86400 ))
      AGE="${DAYS_OLD}d ago"
    else
      AGE="unknown"
    fi
    
    echo "$PLUGIN_KEY: $CHANGES update(s) available (installed $AGE)"
    OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
  fi
done

if [[ $OUTDATED_COUNT -eq 0 ]]; then
  echo "✓ All plugins up to date"
else
  echo ""
  echo "Run /cc upgrade to update outdated plugins"
fi
```

**Output:**
- List of plugins with updates available, showing number of commits
- Age since installation
- Warning if marketplaces are stale
- "All plugins up to date" if nothing to upgrade

**Notes:**
- Checks if specific plugin directory changed in marketplace git history
- Only reports outdated if the plugin itself has commits (not just marketplace changes to other plugins)
- More accurate than comparing marketplace HEAD SHAs which change for any plugin update
- Still warns about stale marketplaces to prompt syncing
