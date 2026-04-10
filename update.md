---
name: cc:update
description: Sync marketplace repo (git pull)
---

# `/cc update`

Pulls latest from the official marketplace git repo. Pure sync, no installs.

## Implementation

```bash
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/claude-plugins-official"

if [[ ! -d "$MARKETPLACE_DIR/.git" ]]; then
  echo "Error: Marketplace repo not found at $MARKETPLACE_DIR"
  exit 1
fi

echo "Updating marketplace catalog..."
cd "$MARKETPLACE_DIR"
git fetch origin
BEFORE=$(git rev-parse HEAD)
git pull origin main
AFTER=$(git rev-parse HEAD)

if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "✓ Marketplace already up to date"
else
  # Count commits added
  NEW_COMMITS=$(git rev-list --count "$BEFORE..$AFTER")
  echo "✓ Updated: $NEW_COMMITS new commit(s)"

  # Show what changed (plugin additions/updates)
  git diff --name-status "$BEFORE" "$AFTER" -- plugins/ | head -n 10
fi
```

**Output:**
- "Already up to date" if no changes
- Count of new commits + preview of changed plugins if updated
