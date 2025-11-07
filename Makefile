.PHONY: lint lint-fix test build docs ci watch watch-cql watch-glaml-extended watch-all binary binary-all mix-deps

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

# Install Mix dependencies (required for building standalone binary)
mix-deps:
	gleam deps download
	ERL_SSL_CACERTFILE=/etc/ssl/cert.pem mix deps.get
	ERL_SSL_CACERTFILE=/etc/ssl/cert.pem mix gleam.deps.get
	@mkdir -p _build/dev/lib
	@for dep in glaml gleam_stdlib gleam_erlang gleam_json gleam_otp gleeunit houdini lustre simplifile argv filepath; do \
		if [ -d "build/dev/erlang/$$dep" ]; then \
			rm -f _build/dev/lib/$$dep; \
			ln -sfn ../../../build/dev/erlang/$$dep _build/dev/lib/$$dep; \
		fi \
	done

# Build standalone binary for current platform
binary: mix-deps
	gleam build
	@rm -f build/dev/erlang/caffeine_lang/_gleam_artefacts/gleam@@compile.erl
	ERL_SSL_CACERTFILE=/etc/ssl/cert.pem mix release

# Build standalone binaries for all platforms (macOS, Linux, Windows)
binary-all: mix-deps
	gleam build
	@rm -f build/dev/erlang/caffeine_lang/_gleam_artefacts/gleam@@compile.erl
	ERL_SSL_CACERTFILE=/etc/ssl/cert.pem mix release --all-targets