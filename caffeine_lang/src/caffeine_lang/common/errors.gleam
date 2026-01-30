import gleam/bool
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string

/// Represents top level compilation errors.
pub type CompilationError {
  // Frontend Phase (parsing .caffeine files)
  FrontendParseError(msg: String)
  FrontendValidationError(msg: String)
  // Parser Phase (part of initial parse & link step)
  ParserFileReadError(msg: String)
  ParserJsonParserError(msg: String)
  ParserDuplicateError(msg: String)
  // Linker Phase (part of initial parse & link step)
  LinkerParseError(msg: String)
  LinkerSemanticError(msg: String)
  // Semantic Analysis Phase
  SemanticAnalysisVendorResolutionError(msg: String)
  SemanticAnalysisTemplateParseError(msg: String)
  SemanticAnalysisTemplateResolutionError(msg: String)
  SemanticAnalysisDependencyValidationError(msg: String)
  // Code Generation Phase
  GeneratorSloQueryResolutionError(msg: String)
  GeneratorDatadogTerraformResolutionError(msg: String)
  // Caffeine Query Language (CQL)
  CQLResolverError(msg: String)
  CQLParserError(msg: String)
  CQLGeneratorError(msg: String)
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
    ParserFileReadError(msg:) -> ParserFileReadError(msg: prefix <> msg)
    ParserJsonParserError(msg:) -> ParserJsonParserError(msg: prefix <> msg)
    ParserDuplicateError(msg:) -> ParserDuplicateError(msg: prefix <> msg)
    LinkerParseError(msg:) -> LinkerParseError(msg: prefix <> msg)
    LinkerSemanticError(msg:) -> LinkerSemanticError(msg: prefix <> msg)
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
    CQLResolverError(msg:) -> CQLResolverError(msg: prefix <> msg)
    CQLParserError(msg:) -> CQLParserError(msg: prefix <> msg)
    CQLGeneratorError(msg:) -> CQLGeneratorError(msg: prefix <> msg)
  }
}

/// Converts a JSON decode error into a CompilationError. Useful for leveraging the
/// custom errors we have per compilation phase vs. the lower level ones from
/// various libraries we leverage.
@internal
pub fn format_json_decode_error(error: json.DecodeError) -> CompilationError {
  let msg = format_json_decode_error_to_string(error)

  ParserJsonParserError(msg:)
}

/// Converts a JSON decode error directly to a string (for browser error messages).
@internal
pub fn format_json_decode_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "Unexpected end of input."
    json.UnexpectedByte(val) -> "Unexpected byte: " <> val <> "."
    json.UnexpectedSequence(val) -> "Unexpected sequence: " <> val <> "."
    json.UnableToDecode(suberrors) -> {
      "Incorrect types: "
      <> suberrors |> format_decode_error_message(option.None, option.None)
    }
  }
}

/// Normalizes type names across targets (JS uses "Array", Erlang uses "List").
fn normalize_type_name(name: String) -> String {
  case name {
    "Array" -> "List"
    other -> other
  }
}

/// Converts a Dynamic value to a short preview string for error messages.
fn dynamic_to_preview_string(value: dynamic.Dynamic) -> String {
  case decode.run(value, decode.string) {
    Ok(s) -> "\"" <> s <> "\""
    _ ->
      case decode.run(value, decode.int) {
        Ok(i) -> int.to_string(i)
        _ ->
          case decode.run(value, decode.float) {
            Ok(f) -> float.to_string(f)
            _ ->
              case decode.run(value, decode.bool) {
                Ok(b) -> bool.to_string(b)
                _ -> dynamic.classify(value)
              }
          }
      }
  }
}

/// Formats a list of decode errors into a human-readable string.
@internal
pub fn format_decode_error_message(
  errors: List(decode.DecodeError),
  type_key_identifier: option.Option(String),
  value: option.Option(dynamic.Dynamic),
) -> String {
  let value_part = case value {
    option.Some(v) -> " value (" <> dynamic_to_preview_string(v) <> ")"
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
