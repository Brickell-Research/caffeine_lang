.PHONY: lint lint-fix test test-js build ci

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

# Run tests for caffeine_lang on JavaScript target
test-js:
	cd caffeine_lang && gleam test --target=javascript

# Run CI pipeline: format check, build, then test
ci: lint build test
