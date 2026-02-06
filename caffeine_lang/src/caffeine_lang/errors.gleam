import caffeine_lang/types.{type ValidationError}
import caffeine_lang/value.{type Value}
import gleam/list
import gleam/option
import gleam/string

/// Represents top level compilation errors.
pub type CompilationError {
  // Frontend Phase (parsing .caffeine files)
  FrontendParseError(msg: String)
  FrontendValidationError(msg: String)
  // Parser Phase (part of initial parse & link step)
  ParserJsonParserError(msg: String)
  ParserDuplicateError(msg: String)
  // Linker Phase (part of initial parse & link step)
  LinkerParseError(msg: String)
  // Semantic Analysis Phase
  SemanticAnalysisVendorResolutionError(msg: String)
  SemanticAnalysisTemplateParseError(msg: String)
  SemanticAnalysisTemplateResolutionError(msg: String)
  SemanticAnalysisDependencyValidationError(msg: String)
  // Code Generation Phase
  GeneratorSloQueryResolutionError(msg: String)
  GeneratorDatadogTerraformResolutionError(msg: String)
  GeneratorHoneycombTerraformResolutionError(msg: String)
  GeneratorDynatraceTerraformResolutionError(msg: String)
  GeneratorNewrelicTerraformResolutionError(msg: String)
  // Caffeine Query Language (CQL)
  CQLResolverError(msg: String)
  CQLParserError(msg: String)
  // Multiple errors accumulated from independent operations.
  CompilationErrors(errors: List(CompilationError))
}

/// Prefixes a CompilationError's message with an identifier string.
/// Useful for adding context like which expectation or blueprint caused the error.
@internal
pub fn prefix_error(
  error: CompilationError,
  identifier: String,
) -> CompilationError {
  let prefix = identifier <> " - "
  case error {
    FrontendParseError(msg:) -> FrontendParseError(msg: prefix <> msg)
    FrontendValidationError(msg:) -> FrontendValidationError(msg: prefix <> msg)
    ParserJsonParserError(msg:) -> ParserJsonParserError(msg: prefix <> msg)
    ParserDuplicateError(msg:) -> ParserDuplicateError(msg: prefix <> msg)
    LinkerParseError(msg:) -> LinkerParseError(msg: prefix <> msg)
    SemanticAnalysisVendorResolutionError(msg:) ->
      SemanticAnalysisVendorResolutionError(msg: prefix <> msg)
    SemanticAnalysisTemplateParseError(msg:) ->
      SemanticAnalysisTemplateParseError(msg: prefix <> msg)
    SemanticAnalysisTemplateResolutionError(msg:) ->
      SemanticAnalysisTemplateResolutionError(msg: prefix <> msg)
    SemanticAnalysisDependencyValidationError(msg:) ->
      SemanticAnalysisDependencyValidationError(msg: prefix <> msg)
    GeneratorSloQueryResolutionError(msg:) ->
      GeneratorSloQueryResolutionError(msg: prefix <> msg)
    GeneratorDatadogTerraformResolutionError(msg:) ->
      GeneratorDatadogTerraformResolutionError(msg: prefix <> msg)
    GeneratorHoneycombTerraformResolutionError(msg:) ->
      GeneratorHoneycombTerraformResolutionError(msg: prefix <> msg)
    GeneratorDynatraceTerraformResolutionError(msg:) ->
      GeneratorDynatraceTerraformResolutionError(msg: prefix <> msg)
    GeneratorNewrelicTerraformResolutionError(msg:) ->
      GeneratorNewrelicTerraformResolutionError(msg: prefix <> msg)
    CQLResolverError(msg:) -> CQLResolverError(msg: prefix <> msg)
    CQLParserError(msg:) -> CQLParserError(msg: prefix <> msg)
    CompilationErrors(errors:) ->
      CompilationErrors(errors: list.map(errors, prefix_error(_, identifier)))
  }
}

/// Flattens a CompilationError into a list of individual errors.
/// Single-error variants become a one-element list; CompilationErrors is unwrapped.
@internal
pub fn to_list(error: CompilationError) -> List(CompilationError) {
  case error {
    CompilationErrors(errors:) -> list.flat_map(errors, to_list)
    _ -> [error]
  }
}

/// Extracts the message from any CompilationError variant.
/// For CompilationErrors, joins all messages with newlines.
@internal
pub fn to_message(error: CompilationError) -> String {
  case error {
    CompilationErrors(errors:) ->
      errors
      |> list.flat_map(to_list)
      |> list.map(to_message)
      |> string.join("\n")
    FrontendParseError(msg:) -> msg
    FrontendValidationError(msg:) -> msg
    ParserJsonParserError(msg:) -> msg
    ParserDuplicateError(msg:) -> msg
    LinkerParseError(msg:) -> msg
    SemanticAnalysisVendorResolutionError(msg:) -> msg
    SemanticAnalysisTemplateParseError(msg:) -> msg
    SemanticAnalysisTemplateResolutionError(msg:) -> msg
    SemanticAnalysisDependencyValidationError(msg:) -> msg
    GeneratorSloQueryResolutionError(msg:) -> msg
    GeneratorDatadogTerraformResolutionError(msg:) -> msg
    GeneratorHoneycombTerraformResolutionError(msg:) -> msg
    GeneratorDynatraceTerraformResolutionError(msg:) -> msg
    GeneratorNewrelicTerraformResolutionError(msg:) -> msg
    CQLResolverError(msg:) -> msg
    CQLParserError(msg:) -> msg
  }
}

/// Collects results from a list of independent operations, accumulating all errors.
/// Returns Ok with all successes if none failed, or an error containing all failures.
@internal
pub fn from_results(
  results: List(Result(a, CompilationError)),
) -> Result(List(a), CompilationError) {
  let #(successes, failures) = partition_results(results, [], [])
  case failures {
    [] -> Ok(list.reverse(successes))
    [single] -> Error(single)
    multiple -> Error(CompilationErrors(errors: list.reverse(multiple)))
  }
}

fn partition_results(
  results: List(Result(a, CompilationError)),
  successes: List(a),
  failures: List(CompilationError),
) -> #(List(a), List(CompilationError)) {
  case results {
    [] -> #(successes, failures)
    [Ok(val), ..rest] -> partition_results(rest, [val, ..successes], failures)
    [Error(err), ..rest] ->
      partition_results(rest, successes, [err, ..failures])
  }
}

/// Normalizes type names across targets (JS uses "Array", Erlang uses "List").
fn normalize_type_name(name: String) -> String {
  case name {
    "Array" -> "List"
    other -> other
  }
}

/// Formats a list of validation errors into a human-readable string.
@internal
pub fn format_validation_error_message(
  errors: List(ValidationError),
  type_key_identifier: option.Option(String),
  val: option.Option(Value),
) -> String {
  let value_part = case val {
    option.Some(v) -> " value (" <> value.to_preview_string(v) <> ")"
    option.None -> ""
  }

  errors
  |> list.map(fn(error) {
    "expected ("
    <> error.expected
    <> ") received ("
    <> normalize_type_name(error.found)
    <> ")"
    <> value_part
    <> " for ("
    <> {
      case { error.path |> string.join(".") }, type_key_identifier {
        "", option.None -> "Unknown"
        path, option.None -> path
        "", option.Some(val) -> val
        path, option.Some(val) -> val <> "." <> path
      }
    }
    <> ")"
  })
  |> string.join(", ")
}
