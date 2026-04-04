.PHONY: lint lint-fix test test-js build ci

# Check code formatting
lint:
	gleam format --check src/ test/

# Fix code formatting
lint-fix:
	gleam format src/ test/

# Build
build:
	gleam build

# Run tests (Erlang target)
test:
	gleam test

# Run tests (JavaScript target)
test-js:
	gleam test --target=javascript

# CI pipeline
ci: lint build test test-js
