# Caffeine

Caffeine is a DSL compiler that generates reliability SLOs (Terraform for Datadog, Honeycomb, Dynatrace, NewRelic) from service expectation definitions. Written in Gleam, compiled to JavaScript and packaged with Bun.

## Architecture Philosophy

**Three packages, three roles:**

- `caffeine_lang` — the pure compiler core. No I/O, no side effects, no knowledge of files or the outside world. Just data-in, data-out transformations. This is where all language intelligence lives.
- `caffeine_lsp` — the LSP intelligence layer. Also pure Gleam, also no direct I/O. Wraps `caffeine_lang` to answer editor questions (diagnostics, hover, completions, etc.). The TypeScript wrapper (`lsp_server.ts`) is only a transport layer — it handles stdin/stdout JSON-RPC framing via `vscode-languageserver-node` and delegates all smarts to compiled Gleam.
- `caffeine_cli` — the thin I/O wrapper. Handles filesystem reads/writes, user-facing output, and argument parsing. Orchestrates `caffeine_lang`. No compiler logic here.

**I/O at the edges only:** `caffeine_lang` is deliberately side-effect-free. `caffeine_cli` and the TypeScript LSP wrapper are the only places that touch the filesystem or stdio. This makes the core easy to test, easy to reason about, and easy to target multiple runtimes.

**Pipeline = typed transformations:** The compilation pipeline is a chain of pure functions, each producing a typed output that is the input to the next. The `IntermediateRepresentation` uses phantom types to track which phase it's in (`Linked` → `DepsValidated` → `Resolved`), making invalid state unrepresentable.

**JS/Bun is the production target:** Gleam compiles to both Erlang and JavaScript. Tests must pass on both (Erlang for correctness, JS for deployment parity). Production binaries are built with `bun build --compile`. Bun was chosen over Deno/Node because Bun's JavaScriptCore engine has tail-call optimization — essential since Gleam has no loops, only tail recursion. This decision is considered settled; don't revisit unless there's a compelling new reason.

**LSP transport is not our code:** The TypeScript LSP server does zero custom JSON-RPC work. `vscode-languageserver-node` handles all framing, parsing, and dispatch. Our TypeScript is a thin bridge: receive message → call Gleam function → return result.

## Project Structure

Gleam monorepo with three packages:

- `caffeine_lang/` - Core compiler library (tokenizer, parser, validator, semantic analyzer, code generator)
- `caffeine_lsp/` - Language Server Protocol implementation (diagnostics, hover, completion, formatting, semantic tokens, go-to-definition, code actions)
- `caffeine_cli/` - CLI wrapping the compiler and LSP (`compile`, `validate`, `format`, `artifacts`, `types`, `lsp`)

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
.caffeine source (MeasurementsFile)
  -> Tokenizer (frontend/tokenizer.gleam)
  -> Parser (frontend/parser.gleam) -> AST (frontend/ast.gleam)
  -> Validator (frontend/validator.gleam)
  -> Lowering (frontend/lowering.gleam) -> Measurement
  -> Linker (linker/linker.gleam) -> IntermediateRepresentation
  -> Semantic Analyzer (analysis/semantic_analyzer.gleam)
  -> Vendor-specific Generator (codegen/datadog.gleam, etc.) -> Terraform HCL

.caffeine source (ExpectsFile)
  -> Tokenizer -> Parser -> Validator -> Lowering -> Expectation
  -> Linker (paired with Measurements) -> IntermediateRepresentation
```

Two file types: `MeasurementsFile` (templates with Requires/Provides) and `ExpectsFile` (concrete instances referencing measurements).

Vendor is derived from the measurement filename (e.g., `datadog.caffeine` -> Datadog vendor). The measurements directory contains one `.caffeine` file per vendor.

## Type System

`AcceptedTypes` is defined in `types.gleam`, which consolidates all type categories into a single module:

- **Primitives**: Boolean, String, Integer, Float, URL, Percentage
- **Collections**: List(T), Dict(K, V)
- **Structured**: Record (named fields with typed values)
- **Modifiers**: Optional(T), Defaulted(T, default)
- **Refinements**: OneOf(T, set), InclusiveRange(T, low, high)

`ParsedType` is a parallel type union used in the frontend pipeline (parser -> validator -> formatter -> lowering). It mirrors `AcceptedTypes` but includes `ParsedTypeAliasRef(String)` for type alias references. During lowering, all `ParsedType` values are resolved into `AcceptedTypes`, eliminating alias references. Downstream code (linker, semantic analyzer, codegen) works exclusively with `AcceptedTypes`.

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
- `LinkerValueValidationError`, `LinkerDuplicateError` (value and uniqueness validation)
- `LinkerParseError` (linker parse step)
- `LinkerVendorResolutionError` (vendor resolution from measurement filename)
- `SemanticAnalysisTemplateParseError`, `SemanticAnalysisTemplateResolutionError`, `SemanticAnalysisDependencyValidationError`
- `GeneratorSloQueryResolutionError`, `GeneratorTerraformResolutionError(vendor, msg, context)`
- `CQLResolverError`, `CQLParserError`

Errors carry an `ErrorContext` with optional identifier, source_path, source_content, location, and suggestion. Errors are prefixed with file paths and identifiers as they bubble up via `errors.prefix_error`.

## LSP

The LSP server (`caffeine_lsp/src/caffeine_lsp/server.gleam`) maintains a `ServerState` with open document text. Features: diagnostics, hover, completion (context-aware with `:` and `[` triggers), document symbols, semantic tokens, go-to-definition, code actions (quickfix), references, rename, signature help, inlay hints, and formatting. Dual runtime support (Erlang + JS/Deno) via FFI bindings.

The LSP detects file type by checking if content starts with `Expectations` (expects file) or otherwise treats it as a measurements file. Diagnostic codes include `MeasurementNotFound`, `DependencyNotFound`, `MissingRequiredFields`, `TypeMismatch`, `UnknownField`, `QuotedFieldName`, and `UnusedExtendable`.

## Language Features

Caffeine is purely declarative - no functions, control flow, variables, or imports. Constructs:
- **Type aliases**: `_env (Type): String { x | x in { prod, staging, dev } }`
- **Extendables**: Reusable Requires/Provides blocks, prefixed with `_`
- **Measurements**: Templates with `Requires` (types) and `Provides` (values), support `extends`. Items are top-level in the file: `"name": Requires { ... } Provides { ... }` (no header, no bullet syntax)
- **Expectations**: `Expectations measured by "measurement_name"` blocks containing named items with `Provides`
- **Unmeasured Expectations**: `Unmeasured Expectations` blocks for expectations with threshold/window_in_days/depends_on but no measurement reference. These participate in dependency graphs but not Terraform generation
- **Dependencies**: Optional `depends_on` field on SLOs: `depends_on: { hard: [...], soft: [...] }`. Declared as a structured record with optional hard/soft lists of dependency references (org.team.service.name format)
- **Template variables**: `$var->attr$` in query strings (lowered to `$$var->attr$$` internally)
- **Comments**: `#` line, `##` section

## Linker / IR Structure

Everything is an SLO. There is no separate `ArtifactType` or `ArtifactData` wrapper.

- `Measurement` (in `linker/measurements.gleam`): Has `name`, `params` (Dict of types), and `inputs` (Dict of values). Validated against SLO params from the standard library (`standard_library/artifacts.gleam`)
- `Expectation` (in `linker/expectations.gleam`): Has `name`, `measurement_ref` (Option -- None for unmeasured), and `inputs`. Measured expectations are validated against their measurement's params; unmeasured expectations are validated against restricted params (threshold, window_in_days, depends_on only)
- `IntermediateRepresentation(phase)` (in `linker/ir.gleam`): Has `metadata`, `unique_identifier`, `values`, `slo: SloFields`, and `vendor: Option(Vendor)`. Phantom type parameter tracks pipeline phase: `Linked` -> `DepsValidated` -> `Resolved`
- `SloFields`: Contains `threshold`, `indicators`, `window_in_days`, `evaluation`, `tags`, `runbook`, and `depends_on` (optional dict of DependencyRelationType -> list of references)
- Unmeasured IRs have `vendor: None` and are filtered out before Terraform generation but included in dependency graph generation

## CLI

- `compile <measurements_dir> <expectations_dir> [output_path]`: Compiles measurements and expectations to Terraform. The measurements directory contains vendor-named `.caffeine` files (e.g., `datadog.caffeine`, `honeycomb.caffeine`). The expectations directory uses fixed three-level depth (org/team/service/file.caffeine)
- `validate <measurements_dir> <expectations_dir>`: Validates without writing output
- `format <path>`: Format `.caffeine` files (with `--check` for CI)
- `artifacts`: List SLO params from the standard library
- `types`: Show the type system reference
- `lsp`: Start the LSP server
- Flags: `--quiet` (suppress progress), `--check` (format check mode), `--target terraform|opentofu`, `--version`/`-v`

## Release

Releases are triggered by git tags (`v*`). The CI workflow compiles cross-platform binaries via Bun (`bun build --compile`), publishes to GitHub Releases, Hex.pm, Homebrew tap, and updates the website's browser bundle. Bun is used (not Deno/Node) because it uses JavaScriptCore which supports TCO — critical since Gleam has no loops, only tail recursion.
