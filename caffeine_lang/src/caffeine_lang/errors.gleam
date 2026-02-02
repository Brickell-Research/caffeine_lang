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
  // Caffeine Query Language (CQL)
  CQLResolverError(msg: String)
  CQLParserError(msg: String)
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
    CQLResolverError(msg:) -> CQLResolverError(msg: prefix <> msg)
    CQLParserError(msg:) -> CQLParserError(msg: prefix <> msg)
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
