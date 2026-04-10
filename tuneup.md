---
name: cc:tuneup
description: Comprehensive maintenance report (update → doctor → outdated)
---

# `/cc tuneup`

Chains diagnostic verbs into one comprehensive report. Changes nothing except `/cc update`'s git pull.

## Implementation

This is a convenience wrapper. Execute the three diagnostic verbs in sequence.

```bash
echo "=== Claude Code Tuneup ==="
echo ""

# Step 1: Update marketplace
echo "Step 1/3: Syncing marketplace..."
echo ""
bash -c "$(cat ~/.claude/skills/cc/update.md | sed -n '/^```bash/,/^```/p' | sed '1d;$d')"

echo ""
echo "---"
echo ""

# Step 2: Run doctor
echo "Step 2/3: Health check..."
echo ""
bash -c "$(cat ~/.claude/skills/cc/doctor.md | sed -n '/^```bash/,/^```/p' | sed '1d;$d')"

echo ""
echo "---"
echo ""

# Step 3: Check for outdated plugins
echo "Step 3/3: Plugin version check..."
echo ""
bash -c "$(cat ~/.claude/skills/cc/outdated.md | sed -n '/^```bash/,/^```/p' | sed '1d;$d')"

echo ""
echo "=== Tuneup Complete ==="
echo ""
echo "Next steps:"
echo "  - Run /cc cleanup to fix detected issues"
echo "  - Run /cc upgrade to update outdated plugins"
```

**Note for Claude:** The actual execution is conceptual. When you receive `/cc tuneup`, execute the logic from `update.md`, `doctor.md`, and `outdated.md` in sequence. Present the combined output as a single report.

**Output:**
Combined output from all three verbs with clear section markers and next-step suggestions.
