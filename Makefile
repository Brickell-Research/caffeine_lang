.PHONY: lint lint-fix test test-e2e build ci watch watch-js lines-of-code

# Check code formatting
lint:
	cd caffeine_lang && gleam format --check
	cd caffeine_lsp && gleam format --check
	cd caffeine_cli && gleam format --check

# Fix code formatting
lint-fix:
	cd caffeine_lang && gleam format
	cd caffeine_lsp && gleam format
	cd caffeine_cli && gleam format

# Build all packages
build:
	cd caffeine_lang && gleam build
	cd caffeine_lsp && gleam build
	cd caffeine_cli && gleam build

# Run tests for all packages (erlang)
test:
	cd caffeine_lang && gleam test
	cd caffeine_lsp && gleam test
	cd caffeine_cli && gleam test

# Run tests for all packages (js)
test-js:
	cd caffeine_lang && gleam test --target=javascript
	cd caffeine_lsp && gleam test --target=javascript
	cd caffeine_cli && gleam test --target=javascript

# Run LSP end-to-end tests
test-e2e:
	cd caffeine_lang && gleam build --target javascript
	cd caffeine_lsp && gleam build --target javascript
	bun test test/lsp_e2e/

test-all: test test-js test-e2e

# Run CI pipeline: format check, build, then test
ci: lint build test

# Watch for changes and run tests automatically
watch:
	@./watch.sh

# Watch for changes and run tests with JavaScript target
watch-js:
	@./watch.sh --target=javascript

# Generate a report of the codebase (per module, cloc-style)
lines-of-code:
	@./scripts/loc.sh
