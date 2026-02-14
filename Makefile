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

# Run tests for all packages
test:
	cd caffeine_lang && gleam test
	cd caffeine_lsp && gleam test
	cd caffeine_cli && gleam test

# Run LSP end-to-end tests
test-e2e:
	cd caffeine_lang && gleam build --target javascript
	cd caffeine_lsp && gleam build --target javascript
	deno test --allow-read --allow-write --allow-env --allow-run test/lsp_e2e/

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
