.PHONY: lint lint-fix test build docs ci watch watch-cql watch-glaml-extended watch-all

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

# Watch for changes and run tests automatically (main project only)
watch:
	@./watch.sh

# Watch CQL package for changes
watch-cql:
	@./watch.sh cql

# Watch glaml_extended package for changes  
watch-glaml-extended:
	@./watch.sh glaml_extended

# Watch all packages for changes
watch-all:
	@./watch.sh all 

# Generate a report of the codebase
lines-of-code:
	cloc . --exclude-dir=node_modules,vendor,dist,.git,build

run-example:
	gleam run -- compile test/artifacts/some_organization/specifications test/artifacts/some_organization
