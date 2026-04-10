---
name: cc:install
description: Install marketplace or git-sourced plugin
---

# `/cc install <plugin-name-or-repo>`

Installs plugins from marketplaces or GitHub repositories.

## Usage Examples

```bash
/cc install superpowers                          # From default marketplace
/cc install obra/superpowers                     # From GitHub (user/repo)
/cc install https://github.com/obra/superpowers  # From GitHub (full URL)
```

## Behavior

**Marketplace plugins** (plain names like `superpowers`):
- Installs from the default `claude-plugins-official` marketplace
- Fast installation (no git clone needed)

**Git-sourced plugins** (patterns like `user/repo` or URLs):
- Automatically adds the repo as a marketplace (if not already added)
- Marketplace name derived from repo (e.g., `obra/superpowers` → marketplace: `superpowers`)
- Marketplace persists even after plugin removal (so future installs are faster)
- Slower first install (requires git clone), but subsequent installs/upgrades are fast

## Implementation

```bash
INPUT="$1"

if [[ -z "$INPUT" ]]; then
  echo "Error: Plugin name or repo required"
  echo "Usage: /cc install <plugin-name>"
  echo ""
  echo "Examples:"
  echo "  /cc install superpowers                   # marketplace plugin"
  echo "  /cc install obra/superpowers              # GitHub repo (user/repo)"
  echo "  /cc install https://github.com/user/repo  # GitHub URL"
  exit 1
fi

# Detect if input is a git source (user/repo pattern or URL)
IS_GIT_SOURCE=false
GIT_SOURCE=""
MARKETPLACE_NAME=""

if [[ "$INPUT" =~ ^https?:// ]]; then
  # Full URL: https://github.com/user/repo or https://github.com/user/repo.git
  IS_GIT_SOURCE=true
  GIT_SOURCE="$INPUT"
  # Extract repo name from URL (last segment without .git)
  MARKETPLACE_NAME=$(basename "$INPUT" .git)
elif [[ "$INPUT" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
  # GitHub shorthand: user/repo
  IS_GIT_SOURCE=true
  GIT_SOURCE="$INPUT"
  # Use repo name as marketplace name
  MARKETPLACE_NAME=$(echo "$INPUT" | cut -d'/' -f2)
else
  # Plain name - marketplace plugin
  PLUGIN_NAME="$INPUT"
fi

# If git source, ensure marketplace exists
if [[ "$IS_GIT_SOURCE" == true ]]; then
  PLUGIN_NAME="$MARKETPLACE_NAME"

  # Check if marketplace already exists
  MARKETPLACE_EXISTS=$(claude plugin marketplace list 2>&1 | grep -c "❯ $MARKETPLACE_NAME" || true)

  if [[ "$MARKETPLACE_EXISTS" -eq 0 ]]; then
    echo "Adding marketplace '$MARKETPLACE_NAME' from $GIT_SOURCE..."
    if ! claude plugin marketplace add "$GIT_SOURCE" 2>&1; then
      echo "Error: Failed to add marketplace from $GIT_SOURCE"
      exit 1
    fi
    echo "✓ Marketplace added"
    echo ""
  else
    echo "Using existing marketplace: $MARKETPLACE_NAME"
  fi

  SOURCE="$MARKETPLACE_NAME"
else
  SOURCE="claude-plugins-official"  # Default marketplace
fi

MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/$SOURCE"
CACHE_DIR="$HOME/.claude/plugins/cache/$SOURCE"
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
BLOCKLIST_FILE="$HOME/.claude/plugins/blocklist.json"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Validate plugin exists in marketplace
PLUGIN_SRC="$MARKETPLACE_DIR/plugins/$PLUGIN_NAME"
if [[ ! -d "$PLUGIN_SRC" ]]; then
  echo "Error: Plugin '$PLUGIN_NAME' not found in marketplace '$SOURCE'"
  if [[ "$SOURCE" == "claude-plugins-official" ]]; then
    echo "Run /cc update to sync latest catalog"
  else
    echo "The marketplace may need to be updated: claude plugin marketplace update $SOURCE"
  fi
  exit 1
fi

# Check if already installed (v2 format)
if [[ -f "$INSTALLED_FILE" ]]; then
  FORMAT_VERSION=$(jq -r '.version // 1' "$INSTALLED_FILE")

  if [[ "$FORMAT_VERSION" -eq 2 ]]; then
    PLUGIN_KEY="$PLUGIN_NAME@$SOURCE"
    ALREADY_INSTALLED=$(jq -r --arg key "$PLUGIN_KEY" '.plugins[$key] // empty' "$INSTALLED_FILE")
    if [[ -n "$ALREADY_INSTALLED" ]]; then
      echo "Plugin '$PLUGIN_NAME@$SOURCE' already installed"
      echo "Use /cc upgrade to update it"
      exit 0
    fi
  fi
fi

# Check blocklist
if [[ -f "$BLOCKLIST_FILE" ]]; then
  BLOCKED=$(jq -r ".blockedPlugins[]? | select(. == \"$PLUGIN_NAME\")" "$BLOCKLIST_FILE")
  if [[ -n "$BLOCKED" ]]; then
    echo "⚠ Warning: Plugin '$PLUGIN_NAME' is in blocklist"
    read -p "Install anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Installation cancelled"
      exit 0
    fi
  fi
fi

# Install to cache
echo "Installing $PLUGIN_NAME..."

# Get version from SKILL.md or plugin.json if available
VERSION="unknown"
if [[ -f "$PLUGIN_SRC/plugin.json" ]]; then
  VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_SRC/plugin.json")
fi

# Create versioned install path
INSTALL_PATH="$CACHE_DIR/$PLUGIN_NAME/$VERSION"
mkdir -p "$(dirname "$INSTALL_PATH")"
cp -R "$PLUGIN_SRC" "$INSTALL_PATH"

# Get current commit SHA
CURRENT_SHA=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Add to installed_plugins.json (v2 format)
if [[ ! -f "$INSTALLED_FILE" ]]; then
  echo '{"version":2,"plugins":{}}' > "$INSTALLED_FILE"
fi

PLUGIN_KEY="$PLUGIN_NAME@$SOURCE"
jq --arg key "$PLUGIN_KEY" \
   --arg scope "user" \
   --arg path "$INSTALL_PATH" \
   --arg version "$VERSION" \
   --arg sha "$CURRENT_SHA" \
   --arg now "$NOW" \
  '.version = 2 |
   .plugins[$key] = [{
     "scope": $scope,
     "installPath": $path,
     "version": $version,
     "installedAt": $now,
     "lastUpdated": $now,
     "gitCommitSha": $sha
   }]' \
  "$INSTALLED_FILE" > "$INSTALLED_FILE.tmp"
mv "$INSTALLED_FILE.tmp" "$INSTALLED_FILE"

# Enable in settings.json
if [[ -f "$SETTINGS_FILE" ]]; then
  # Add to marketplace.enabled array if not present
  jq --arg name "$PLUGIN_NAME" \
    '.marketplace.enabled = (.marketplace.enabled // []) |
     if (.marketplace.enabled | index($name)) == null then
       .marketplace.enabled += [$name]
     else . end' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
fi

echo "✓ Installed $PLUGIN_NAME@$SOURCE at ${CURRENT_SHA:0:7}"
```

**Output:**

For marketplace plugins:
```
Installing superpowers...
✓ Installed superpowers@claude-plugins-official at 6e43e87
```

For git-sourced plugins:
```
Adding marketplace 'superpowers' from obra/superpowers...
✓ Marketplace added

Installing superpowers...
✓ Installed superpowers@superpowers at a1b2c3d
```

**Notes for Future You:**

- Git-sourced plugins create persistent marketplace entries. They stay in your marketplace list even after uninstalling the plugin, so reinstalls are faster.
- You can see all marketplaces with `claude plugin marketplace list`
- Remove unused marketplaces with `claude plugin marketplace remove <name>`
- The marketplace name is derived from the repo name (last segment of user/repo or URL)
