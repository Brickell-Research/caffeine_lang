.PHONY: lint lint-fix test build docs ci watch

# Check code formatting
lint:
	gleam format --check

# Fix code formatting
lint-fix:
	gleam format

# Build the project
build:
	gleam build

# Run tests
test:
	gleam test

# Run CI pipeline: format check, build, then test
ci: lint build test

# Generate documentation (if needed)
docs:
	@echo "Documentation generation not configured yet"

# Watch for changes and run tests automatically
watch:
	@./watch.sh 
