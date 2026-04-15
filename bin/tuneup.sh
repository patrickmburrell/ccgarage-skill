#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Claude Code Tuneup ==="
echo ""

# Step 1: Update marketplace
echo "Step 1/3: Syncing marketplace..."
echo ""
"$SCRIPT_DIR/update.sh"

echo ""
echo "---"
echo ""

# Step 2: Run doctor
echo "Step 2/3: Health check..."
echo ""
"$SCRIPT_DIR/doctor.sh"

echo ""
echo "---"
echo ""

# Step 3: Check for outdated plugins
echo "Step 3/3: Plugin version check..."
echo ""
"$SCRIPT_DIR/outdated.sh"

echo ""
echo "=== Tuneup Complete ==="
echo ""
echo "Next steps:"
echo "  - Run /cc cleanup to fix detected issues"
echo "  - Run /cc upgrade to update outdated plugins"
