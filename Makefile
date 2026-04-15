.PHONY: sync clean test

# Extract bash blocks from .md files to bin/*.sh scripts
sync:
	@echo "Syncing .sh scripts from .md files..."
	@mkdir -p bin
	@for file in *.md; do \
		if [ "$$file" = "SKILL.md" ] || [ "$$file" = "README.md" ]; then \
			continue; \
		fi; \
		name=$$(basename "$$file" .md); \
		echo "  Extracting bin/$${name}.sh..."; \
		( \
			echo '#!/usr/bin/env bash'; \
			echo 'set -euo pipefail'; \
			echo ''; \
			sed -n '/^```bash/,/^```$$/p' "$$file" | sed '1d;$$d'; \
		) > "bin/$${name}.sh"; \
		chmod +x "bin/$${name}.sh"; \
	done
	@echo "✓ Sync complete"

# Clean generated files
clean:
	@echo "Cleaning generated bin/ directory..."
	@rm -rf bin/
	@echo "✓ Clean complete"

# Test that scripts execute without errors (syntax check only)
test:
	@echo "Testing scripts..."
	@for script in bin/*.sh; do \
		echo "  Testing $$script..."; \
		bash -n "$$script" || exit 1; \
	done
	@echo "✓ All scripts pass syntax check"
