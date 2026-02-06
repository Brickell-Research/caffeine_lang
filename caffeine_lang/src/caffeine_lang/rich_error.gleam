/// Enriched error type with structured location and diagnostic data.
/// Wraps a CompilationError with source context for rendering.
import caffeine_lang/errors.{type CompilationError}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// An enriched error with structured location and diagnostic data.
pub type RichError {
  RichError(
    error: CompilationError,
    code: ErrorCode,
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

/// Machine-readable error code.
pub type ErrorCode {
  ErrorCode(phase: String, number: Int)
}

/// Converts an ErrorCode to its display string (e.g., "E103").
pub fn error_code_to_string(code: ErrorCode) -> String {
  let s = int.to_string(code.number)
  let padding = 3 - string.length(s)
  case padding > 0 {
    True -> "E" <> string.repeat("0", padding) <> s
    False -> "E" <> s
  }
}

/// Assigns an error code based on the CompilationError variant.
pub fn error_code_for(error: CompilationError) -> ErrorCode {
  case error {
    errors.FrontendParseError(..) -> ErrorCode("parse", 100)
    errors.FrontendValidationError(..) -> ErrorCode("validation", 200)
    errors.ParserJsonParserError(..) -> ErrorCode("linker", 302)
    errors.ParserDuplicateError(..) -> ErrorCode("linker", 303)
    errors.LinkerParseError(..) -> ErrorCode("linker", 301)
    errors.SemanticAnalysisVendorResolutionError(..) ->
      ErrorCode("semantic", 401)
    errors.SemanticAnalysisTemplateParseError(..) -> ErrorCode("semantic", 402)
    errors.SemanticAnalysisTemplateResolutionError(..) ->
      ErrorCode("semantic", 403)
    errors.SemanticAnalysisDependencyValidationError(..) ->
      ErrorCode("semantic", 404)
    errors.GeneratorSloQueryResolutionError(..) -> ErrorCode("codegen", 501)
    errors.GeneratorDatadogTerraformResolutionError(..) ->
      ErrorCode("codegen", 502)
    errors.GeneratorHoneycombTerraformResolutionError(..) ->
      ErrorCode("codegen", 503)
    errors.GeneratorDynatraceTerraformResolutionError(..) ->
      ErrorCode("codegen", 504)
    errors.GeneratorNewrelicTerraformResolutionError(..) ->
      ErrorCode("codegen", 505)
    errors.CQLResolverError(..) -> ErrorCode("cql", 601)
    errors.CQLParserError(..) -> ErrorCode("cql", 602)
    errors.CompilationErrors(..) -> ErrorCode("multiple", 0)
  }
}

/// Creates a RichError with minimal context (no source, no location, no suggestion).
pub fn from_compilation_error(error: CompilationError) -> RichError {
  RichError(
    error:,
    code: error_code_for(error),
    source_path: option.None,
    source_content: option.None,
    location: option.None,
    suggestion: option.None,
  )
}

/// Flattens a CompilationError into a list of RichErrors.
/// Unwraps CompilationErrors into individual RichErrors.
pub fn from_compilation_errors(error: CompilationError) -> List(RichError) {
  error
  |> errors.to_list
  |> list.map(from_compilation_error)
}

/// Extracts the human-readable message from a CompilationError.
/// Delegates to errors.to_message for consistent behavior.
pub fn error_message(error: CompilationError) -> String {
  errors.to_message(error)
}
