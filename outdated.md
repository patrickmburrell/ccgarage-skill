---
name: cc:outdated
description: Compare installed plugins vs. marketplace HEAD
---

# `/cc outdated`

Compares installed plugin commit SHAs against marketplace HEAD.

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

# Cache HEAD SHAs per source and check staleness
declare -A SOURCE_HEAD_SHA
declare -A SOURCE_STALE

# Get unique sources from installed plugins
while IFS= read -r SOURCE; do
  MARKETPLACE_DIR="$MARKETPLACES_DIR/$SOURCE"

  if [[ ! -d "$MARKETPLACE_DIR/.git" ]]; then
    echo "⚠ Marketplace not found: $SOURCE"
    continue
  fi

  # Get HEAD commit for this source
  SOURCE_HEAD_SHA["$SOURCE"]=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD 2>/dev/null || echo "")

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

# Parse v2 format and compare SHAs
jq -r '.plugins | to_entries[] | "\(.key | split("@")[0])|\(.key | split("@")[1])|\(.value[0].gitCommitSha // "unknown")|\(.value[0].installedAt // "unknown")"' "$INSTALLED_FILE" | \
while IFS='|' read -r NAME SOURCE INSTALLED_SHA INSTALLED_AT; do
  HEAD_SHA="${SOURCE_HEAD_SHA[$SOURCE]}"

  if [[ -z "$HEAD_SHA" ]]; then
    continue  # Skip if marketplace wasn't found
  fi

  if [[ "$INSTALLED_SHA" != "$HEAD_SHA" ]]; then
    # Calculate age
    if [[ "$INSTALLED_AT" != "unknown" ]]; then
      INSTALLED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${INSTALLED_AT%Z}" +%s 2>/dev/null || echo "$NOW")
      DAYS_OLD=$(( (NOW - INSTALLED_TS) / 86400 ))
      AGE="${DAYS_OLD}d ago"
    else
      AGE="unknown"
    fi

    echo "$NAME@$SOURCE: ${INSTALLED_SHA:0:7} → ${HEAD_SHA:0:7} (installed $AGE)"
  fi
done | tee /tmp/cc-outdated.txt

if [[ ! -s /tmp/cc-outdated.txt ]]; then
  echo "✓ All plugins up to date"
fi

rm -f /tmp/cc-outdated.txt
```

**Output:**
- Table of plugin name, old SHA, new SHA, age since install
- Suggests `/cc update` if marketplace is stale
- "All plugins up to date" if nothing to upgrade
