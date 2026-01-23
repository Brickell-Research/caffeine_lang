.PHONY: lint lint-fix test build ci watch watch-js lines-of-code

# Check code formatting
lint:
	cd caffeine_lang && gleam format --check
	cd caffeine_cli && gleam format --check

# Fix code formatting
lint-fix:
	cd caffeine_lang && gleam format
	cd caffeine_cli && gleam format

# Build both packages
build:
	cd caffeine_lang && gleam build
	cd caffeine_cli && gleam build

# Run tests for both packages
test:
	cd caffeine_lang && gleam test
	cd caffeine_cli && gleam test

# Run CI pipeline: format check, build, then test
ci: lint build test

# Watch for changes and run tests automatically
watch:
	@./watch.sh

# Watch for changes and run tests with JavaScript target
watch-js:
	@./watch.sh --target=javascript

# Generate a report of the codebase
lines-of-code:
	cloc . --exclude-dir=node_modules,vendor,dist,.git,build
