.PHONY: lint-fix test type-check ci

# Run RuboCop linter
lint-fix:
	bundle exec rubocop -A

# Run Sorbet type checker
type-check:
	bundle exec srb tc

# Run RSpec tests
test:
	bundle exec rspec

# Run CI pipeline: lint, type-check, then test
ci: lint-fix type-check test 
