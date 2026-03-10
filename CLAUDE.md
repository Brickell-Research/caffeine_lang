# Caffeine

Caffeine is a DSL compiler that generates reliability artifacts (Terraform for Datadog SLOs) from service expectation definitions. Written in Gleam, targeting Erlang.

## Project Structure

Gleam monorepo with three packages:

- `caffeine_lang/` - Core compiler library (tokenizer, parser, validator, semantic analyzer, code generator)
- `caffeine_lsp/` - Language Server Protocol implementation (diagnostics, hover, completion, formatting, semantic tokens, go-to-definition, code actions)
- `caffeine_cli/` - CLI wrapping the compiler and LSP (`compile`, `format`, `artifacts`, `types`, `lsp`)

## Commands

```bash
make build        # Build all three packages
make test         # Run tests for all packages (Erlang target)
make lint         # Check formatting (gleam format --check)
make lint-fix     # Fix formatting
make ci           # lint + build + test
make watch        # Auto-test on file changes (uses fswatch)
make watch-js     # Auto-test with JavaScript target
```

To test a single package: `cd caffeine_lang && gleam test`

IMPORTANT: Tests must pass on the Erlang target. `caffeine_lang` must also pass on JavaScript:
```bash
cd caffeine_lang && gleam test && gleam test --target javascript
cd caffeine_lsp && gleam test
cd caffeine_cli && gleam test
```

## Compilation Pipeline

```
.caffeine source
  -> Tokenizer (frontend/tokenizer.gleam)
  -> Parser (frontend/parser.gleam) -> AST (frontend/ast.gleam)
  -> Validator (frontend/validator.gleam)
  -> Lowering (frontend/lowering.gleam)
  -> Linker (linker/linker.gleam) -> IntermediateRepresentation
  -> Semantic Analyzer (analysis/semantic_analyzer.gleam)
  -> Datadog Generator (codegen/datadog.gleam) -> Terraform HCL
```

Two file types: `BlueprintsFile` (templates with Requires/Provides) and `ExpectsFile` (fully configured instances).

## Type System

`AcceptedTypes` is defined in `types.gleam`, which consolidates all type categories into a single module:

- **Primitives**: Boolean, String, Integer, Float, URL
- **Collections**: List(T), Dict(K, V)
- **Modifiers**: Optional(T), Defaulted(T, default)
- **Refinements**: OneOf(T, set), InclusiveRange(T, low, high)

`ParsedType` is a parallel type union used in the frontend pipeline (parser → validator → formatter → lowering). It mirrors `AcceptedTypes` but includes `ParsedTypeAliasRef(String)` for type alias references. During lowering, all `ParsedType` values are resolved into `AcceptedTypes`, eliminating alias references. Downstream code (linker, semantic analyzer, codegen) works exclusively with `AcceptedTypes`.

All type operations (parsing, validation, string conversion, resolution) live in `types.gleam`. Sub-type functions are private; the module exposes dispatch functions that route to the correct sub-type handler.

## Coding Style

IMPORTANT: Follow the conventions in @style.md

Key points:
- Import types unqualified, use qualified imports for everything else
- Data-first arguments to enable piping
- `bool.guard` instead of case on booleans
- `Result` + `result.try` chains for error handling, never exceptions
- Tail recursion: public wrapper calls private `_loop` with accumulator, prepends to list, reverses at end
- `@internal pub fn` for test-exposed functions, plain `fn` for truly private
- Doc comments (`///`) required on all `pub` items

## Testing

- Framework: gleeunit
- Test files mirror `src/` directory structure
- Use `test_helpers.array_based_test_executor_*` for parameterized tests
- Corpus-based tests in `test/caffeine_lang/corpus/` and `test/caffeine_cli/corpus/` for snapshot-style comparisons
- Formatter tests verify idempotency: `format(format(x)) == format(x)`
- Test comments: `// ==== function_name ====` headers with `// * ✅ case` descriptions

## Error Handling

`CompilationError` in `errors.gleam` has phase-specific variants:
- `FrontendParseError`, `FrontendValidationError` (tokenizer/parser/validator)
- `LinkerValueValidationError`, `LinkerDuplicateError`
- `LinkerParseError`
- `SemanticAnalysisVendorResolutionError`, `SemanticAnalysisTemplateParseError`, `SemanticAnalysisTemplateResolutionError`, `SemanticAnalysisDependencyValidationError`
- `GeneratorSloQueryResolutionError`, `GeneratorDatadogTerraformResolutionError`, `GeneratorHoneycombTerraformResolutionError`
- `CQLResolverError`, `CQLParserError`

Errors are prefixed with file paths and identifiers as they bubble up via `errors.prefix_error`.

## LSP

The LSP server (`caffeine_lsp/src/caffeine_lsp/server.gleam`) is a pure Gleam implementation targeting Erlang. It communicates via JSON-RPC over stdin/stdout with Content-Length framing. Features: diagnostics, hover, completion (context-aware with `:` and `[` triggers), document symbols, semantic tokens, go-to-definition, code actions (quickfix), formatting, references, rename, type hierarchy, and workspace symbols.

## Language Features

Caffeine is purely declarative - no functions, control flow, variables, or imports. Constructs:
- **Type aliases**: `_env (Type): String { x | x in { prod, staging, dev } }`
- **Extendables**: Reusable Requires/Provides blocks, prefixed with `_`
- **Blueprints**: Templates with `Requires` (types) and `Provides` (values), support `extends`
- **Expectations**: Fully configured blueprints, only `Provides`
- **Template variables**: `$var->attr$` in query strings
- **Comments**: `#` line, `##` section

## Building

Nix flake (`flake.nix`) provides:
- `nix develop` — dev shell with Gleam, Erlang 27, rebar3, Bun, Node 20
- `nix build` — erlang-shipment wrapped as `bin/caffeine` (requires Nix Erlang)
- `nix build .#shipment` — raw erlang-shipment (BEAM bytecode)

Manual build: `cd caffeine_cli && gleam export erlang-shipment` produces portable BEAM files in `build/erlang-shipment/`. Requires Erlang/OTP 27+ on the target machine.

## Release

Releases are triggered by git tags (`v*`). The CI workflow:
1. **Matrix build** (5 runners): Linux x64/ARM64, macOS x64/ARM64, Windows x64. Each builds an erlang-shipment, bundles ERTS (Erlang runtime) for standalone execution — no Erlang needed on the user's machine.
2. **Release job**: Creates GitHub Release with platform tarballs/zips, publishes to Hex.pm (caffeine_lang), builds browser bundle (esbuild via Bun), updates the website.
