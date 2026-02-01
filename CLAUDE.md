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

IMPORTANT: Tests must pass on both Erlang and JavaScript targets. Always verify with:
```bash
cd caffeine_lang && gleam test && gleam test --target javascript
cd caffeine_lsp && gleam test && gleam test --target javascript
cd caffeine_cli && gleam test && gleam test --target javascript
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

`AcceptedTypes` is defined in `common/types.gleam`, which consolidates all type categories into a single module:

- **Primitives**: Boolean, String, Integer, Float, URL
- **Collections**: List(T), Dict(K, V)
- **Modifiers**: Optional(T), Defaulted(T, default)
- **Refinements**: OneOf(T, set), InclusiveRange(T, low, high)
- **TypeAliasRef**: Named type references resolved at compile-time

All type operations (parsing, validation, string conversion, resolution) live in `common/types.gleam`. Sub-type functions are private; the module exposes dispatch functions that route to the correct sub-type handler.

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

`CompilationError` in `common/errors.gleam` has phase-specific variants:
- `FrontendParseError`, `FrontendValidationError` (tokenizer/parser/validator)
- `ParserFileReadError`, `ParserJsonParserError`, `ParserDuplicateError`
- `LinkerParseError`, `LinkerSemanticError`
- `SemanticAnalysis*Error` (vendor, template, dependency)
- `Generator*Error` (SLO query, Terraform)

Errors are prefixed with file paths and identifiers as they bubble up via `errors.prefix_error`.

## LSP

The LSP server (`caffeine_lsp/src/caffeine_lsp/server.gleam`) maintains a `ServerState` with open document text. Features: diagnostics, hover, completion (context-aware with `:` and `[` triggers), document symbols, semantic tokens, go-to-definition, code actions (quickfix), and formatting. Dual runtime support (Erlang + JS/Deno) via FFI bindings.

## Language Features

Caffeine is purely declarative - no functions, control flow, variables, or imports. Constructs:
- **Type aliases**: `_env (Type): String { x | x in { prod, staging, dev } }`
- **Extendables**: Reusable Requires/Provides blocks, prefixed with `_`
- **Blueprints**: Templates with `Requires` (types) and `Provides` (values), support `extends`
- **Expectations**: Fully configured blueprints, only `Provides`
- **Template variables**: `$var->attr$` in query strings
- **Comments**: `#` line, `##` section

## Release

Releases are triggered by git tags (`v*`). The CI workflow compiles cross-platform binaries via Deno, publishes to GitHub Releases, Hex.pm, Homebrew tap, and updates the website's browser bundle.
