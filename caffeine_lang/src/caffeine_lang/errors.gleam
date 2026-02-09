import caffeine_lang/types.{type ValidationError}
import caffeine_lang/value.{type Value}
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Structured context attached to every compilation error.
pub type ErrorContext {
  ErrorContext(
    identifier: Option(String),
    source_path: Option(String),
    source_content: Option(String),
    location: Option(SourceLocation),
    suggestion: Option(String),
  )
}

/// A source location within a file (1-indexed).
pub type SourceLocation {
  SourceLocation(line: Int, column: Int, end_column: Option(Int))
}

/// Returns an ErrorContext with all fields set to None.
pub fn empty_context() -> ErrorContext {
  ErrorContext(
    identifier: option.None,
    source_path: option.None,
    source_content: option.None,
    location: option.None,
    suggestion: option.None,
  )
}

/// Represents top level compilation errors.
pub type CompilationError {
  // Frontend Phase (parsing .caffeine files)
  FrontendParseError(msg: String, context: ErrorContext)
  FrontendValidationError(msg: String, context: ErrorContext)
  // Linker Phase (value and uniqueness validation)
  LinkerValueValidationError(msg: String, context: ErrorContext)
  LinkerDuplicateError(msg: String, context: ErrorContext)
  // Linker Phase (parse step)
  LinkerParseError(msg: String, context: ErrorContext)
  // Linker Phase (vendor resolution)
  LinkerVendorResolutionError(msg: String, context: ErrorContext)
  // Semantic Analysis Phase
  SemanticAnalysisTemplateParseError(msg: String, context: ErrorContext)
  SemanticAnalysisTemplateResolutionError(msg: String, context: ErrorContext)
  SemanticAnalysisDependencyValidationError(msg: String, context: ErrorContext)
  // Code Generation Phase
  GeneratorSloQueryResolutionError(msg: String, context: ErrorContext)
  GeneratorTerraformResolutionError(
    vendor: String,
    msg: String,
    context: ErrorContext,
  )
  // Caffeine Query Language (CQL)
  CQLResolverError(msg: String, context: ErrorContext)
  CQLParserError(msg: String, context: ErrorContext)
  // Multiple errors accumulated from independent operations.
  CompilationErrors(errors: List(CompilationError))
}

// ==== Smart constructors ====

/// Creates a FrontendParseError with empty context.
pub fn frontend_parse_error(msg msg: String) -> CompilationError {
  FrontendParseError(msg:, context: empty_context())
}

/// Creates a FrontendValidationError with empty context.
pub fn frontend_validation_error(msg msg: String) -> CompilationError {
  FrontendValidationError(msg:, context: empty_context())
}

/// Creates a LinkerValueValidationError with empty context.
pub fn linker_value_validation_error(msg msg: String) -> CompilationError {
  LinkerValueValidationError(msg:, context: empty_context())
}

/// Creates a LinkerDuplicateError with empty context.
pub fn linker_duplicate_error(msg msg: String) -> CompilationError {
  LinkerDuplicateError(msg:, context: empty_context())
}

/// Creates a LinkerParseError with empty context.
pub fn linker_parse_error(msg msg: String) -> CompilationError {
  LinkerParseError(msg:, context: empty_context())
}

/// Creates a LinkerVendorResolutionError with empty context.
pub fn linker_vendor_resolution_error(msg msg: String) -> CompilationError {
  LinkerVendorResolutionError(msg:, context: empty_context())
}

/// Creates a SemanticAnalysisTemplateParseError with empty context.
pub fn semantic_analysis_template_parse_error(
  msg msg: String,
) -> CompilationError {
  SemanticAnalysisTemplateParseError(msg:, context: empty_context())
}

/// Creates a SemanticAnalysisTemplateResolutionError with empty context.
pub fn semantic_analysis_template_resolution_error(
  msg msg: String,
) -> CompilationError {
  SemanticAnalysisTemplateResolutionError(msg:, context: empty_context())
}

/// Creates a SemanticAnalysisDependencyValidationError with empty context.
pub fn semantic_analysis_dependency_validation_error(
  msg msg: String,
) -> CompilationError {
  SemanticAnalysisDependencyValidationError(msg:, context: empty_context())
}

/// Creates a GeneratorSloQueryResolutionError with empty context.
pub fn generator_slo_query_resolution_error(msg msg: String) -> CompilationError {
  GeneratorSloQueryResolutionError(msg:, context: empty_context())
}

/// Creates a GeneratorTerraformResolutionError with empty context.
pub fn generator_terraform_resolution_error(
  vendor vendor: String,
  msg msg: String,
) -> CompilationError {
  GeneratorTerraformResolutionError(vendor:, msg:, context: empty_context())
}

/// Creates a CQLResolverError with empty context.
pub fn cql_resolver_error(msg msg: String) -> CompilationError {
  CQLResolverError(msg:, context: empty_context())
}

/// Creates a CQLParserError with empty context.
pub fn cql_parser_error(msg msg: String) -> CompilationError {
  CQLParserError(msg:, context: empty_context())
}

/// Extracts the ErrorContext from any CompilationError variant.
@internal
pub fn error_context(error: CompilationError) -> ErrorContext {
  case error {
    FrontendParseError(context:, ..) -> context
    FrontendValidationError(context:, ..) -> context
    LinkerValueValidationError(context:, ..) -> context
    LinkerDuplicateError(context:, ..) -> context
    LinkerParseError(context:, ..) -> context
    LinkerVendorResolutionError(context:, ..) -> context
    SemanticAnalysisTemplateParseError(context:, ..) -> context
    SemanticAnalysisTemplateResolutionError(context:, ..) -> context
    SemanticAnalysisDependencyValidationError(context:, ..) -> context
    GeneratorSloQueryResolutionError(context:, ..) -> context
    GeneratorTerraformResolutionError(context:, ..) -> context
    CQLResolverError(context:, ..) -> context
    CQLParserError(context:, ..) -> context
    CompilationErrors(..) -> empty_context()
  }
}

/// Prefixes a CompilationError's message with an identifier string.
/// Also sets the context.identifier field for structured access.
@internal
pub fn prefix_error(
  error: CompilationError,
  identifier: String,
) -> CompilationError {
  let prefix = identifier <> " - "
  case error {
    FrontendParseError(msg:, context:) ->
      FrontendParseError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    FrontendValidationError(msg:, context:) ->
      FrontendValidationError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    LinkerValueValidationError(msg:, context:) ->
      LinkerValueValidationError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    LinkerDuplicateError(msg:, context:) ->
      LinkerDuplicateError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    LinkerParseError(msg:, context:) ->
      LinkerParseError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    LinkerVendorResolutionError(msg:, context:) ->
      LinkerVendorResolutionError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    SemanticAnalysisTemplateParseError(msg:, context:) ->
      SemanticAnalysisTemplateParseError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    SemanticAnalysisTemplateResolutionError(msg:, context:) ->
      SemanticAnalysisTemplateResolutionError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    SemanticAnalysisDependencyValidationError(msg:, context:) ->
      SemanticAnalysisDependencyValidationError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    GeneratorSloQueryResolutionError(msg:, context:) ->
      GeneratorSloQueryResolutionError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    GeneratorTerraformResolutionError(vendor:, msg:, context:) ->
      GeneratorTerraformResolutionError(
        vendor:,
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    CQLResolverError(msg:, context:) ->
      CQLResolverError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    CQLParserError(msg:, context:) ->
      CQLParserError(
        msg: prefix <> msg,
        context: set_context_identifier(context, identifier),
      )
    CompilationErrors(errors:) ->
      CompilationErrors(errors: list.map(errors, prefix_error(_, identifier)))
  }
}

/// Sets the identifier field on an ErrorContext, preserving existing value if already set.
fn set_context_identifier(
  context: ErrorContext,
  identifier: String,
) -> ErrorContext {
  case context.identifier {
    option.Some(_) -> context
    option.None -> ErrorContext(..context, identifier: option.Some(identifier))
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
    FrontendParseError(msg:, ..) -> msg
    FrontendValidationError(msg:, ..) -> msg
    LinkerValueValidationError(msg:, ..) -> msg
    LinkerDuplicateError(msg:, ..) -> msg
    LinkerParseError(msg:, ..) -> msg
    LinkerVendorResolutionError(msg:, ..) -> msg
    SemanticAnalysisTemplateParseError(msg:, ..) -> msg
    SemanticAnalysisTemplateResolutionError(msg:, ..) -> msg
    SemanticAnalysisDependencyValidationError(msg:, ..) -> msg
    GeneratorSloQueryResolutionError(msg:, ..) -> msg
    GeneratorTerraformResolutionError(msg:, ..) -> msg
    CQLResolverError(msg:, ..) -> msg
    CQLParserError(msg:, ..) -> msg
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
