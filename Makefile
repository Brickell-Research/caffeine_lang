.PHONY: lint-fix test type-check ci

# Run RuboCop linter
lint-fix:
	rubocop -A

# Run Sorbet type checker
type-check:
	srb tc

# Run RSpec tests
test:
	rspec

# Run CI pipeline: lint, type-check, then test
ci: lint-fix type-check test 
