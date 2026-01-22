import gleam/dynamic/decode
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
      <> suberrors |> format_decode_error_message(option.None)
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

/// Formats a list of decode errors into a human-readable string.
@internal
pub fn format_decode_error_message(
  errors: List(decode.DecodeError),
  type_key_identifier: option.Option(String),
) -> String {
  errors
  |> list.map(fn(error) {
    "expected ("
    <> error.expected
    <> ") received ("
    <> normalize_type_name(error.found)
    <> ") for ("
    <> {
      case { error.path |> string.join(".") }, type_key_identifier {
        "", option.None -> "Unknown"
        _, option.None -> {
          error.path |> string.join(".")
        }
        "", option.Some(val) -> val
        _, _ -> {
          error.path |> string.join(".")
        }
      }
    }
    <> ")"
  })
  |> string.join(", ")
}
