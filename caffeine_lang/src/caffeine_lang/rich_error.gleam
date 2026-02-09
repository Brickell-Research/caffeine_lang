/// Enriched error type with structured location and diagnostic data.
/// Wraps a CompilationError with source context for rendering.
import caffeine_lang/constants
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
    location: Option(errors.SourceLocation),
    suggestion: Option(String),
  )
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
    errors.LinkerValueValidationError(..) -> ErrorCode("linker", 302)
    errors.LinkerDuplicateError(..) -> ErrorCode("linker", 303)
    errors.LinkerParseError(..) -> ErrorCode("linker", 301)
    errors.SemanticAnalysisVendorResolutionError(..) ->
      ErrorCode("semantic", 401)
    errors.SemanticAnalysisTemplateParseError(..) -> ErrorCode("semantic", 402)
    errors.SemanticAnalysisTemplateResolutionError(..) ->
      ErrorCode("semantic", 403)
    errors.SemanticAnalysisDependencyValidationError(..) ->
      ErrorCode("semantic", 404)
    errors.GeneratorSloQueryResolutionError(..) -> ErrorCode("codegen", 501)
    errors.GeneratorTerraformResolutionError(vendor:, ..) ->
      vendor_to_error_code(vendor)
    errors.CQLResolverError(..) -> ErrorCode("cql", 601)
    errors.CQLParserError(..) -> ErrorCode("cql", 602)
    errors.CompilationErrors(..) -> ErrorCode("multiple", 0)
  }
}

/// Creates a RichError, extracting context from the error's ErrorContext.
pub fn from_compilation_error(error: CompilationError) -> RichError {
  let ctx = errors.error_context(error)
  RichError(
    error:,
    code: error_code_for(error),
    source_path: ctx.source_path,
    source_content: ctx.source_content,
    location: ctx.location,
    suggestion: ctx.suggestion,
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

/// Maps a vendor string to its codegen error code.
fn vendor_to_error_code(vendor: String) -> ErrorCode {
  case vendor {
    v if v == constants.vendor_datadog -> ErrorCode("codegen", 502)
    v if v == constants.vendor_honeycomb -> ErrorCode("codegen", 503)
    v if v == constants.vendor_dynatrace -> ErrorCode("codegen", 504)
    v if v == constants.vendor_newrelic -> ErrorCode("codegen", 505)
    _ -> ErrorCode("codegen", 500)
  }
}
