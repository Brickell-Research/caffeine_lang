import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/string

/// Represents errors that can occur during the parsing phase of compilation.
pub type ParseError {
  FileReadError(msg: String)
  JsonParserError(msg: String)
  DuplicateError(msg: String)
}

/// Represents errors that can occur during the linking phase of compilation.
pub type LinkerError {
  LinkerParseError(msg: String)
  LinkerSemanticError(msg: String)
}

/// Represents errors that can occur during semantic analysis.
pub type SemanticError {
  VendorResolutionError(msg: String)
  TemplateParseError(msg: String)
  TemplateResolutionError(msg: String)
}

// =============================================================================
// JSON Decode Error Formatting
// =============================================================================

/// Converts a JSON decode error into a ParseError. Useful for leveraging the
/// custom errors we have per compilation phase vs. the lower level ones from
/// various libraries we leverage.
pub fn format_json_decode_error(error: json.DecodeError) -> ParseError {
  let msg = json_error_to_string(error)

  JsonParserError(msg:)
}

fn json_error_to_string(error: json.DecodeError) -> String {
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

/// Formats a list of decode errors into a human-readable string.
pub fn format_decode_error_message(
  errors: List(decode.DecodeError),
  type_key_identifier: option.Option(String),
) -> String {
  errors
  |> list.map(fn(error) {
    "expected ("
    <> error.expected
    <> ") received ("
    <> error.found
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

pub fn parser_error_to_linker_error(error: ParseError) -> LinkerError {
  case error {
    FileReadError(msg) -> LinkerParseError("File read error: " <> msg)
    JsonParserError(msg) -> LinkerParseError("JSON parse error: " <> msg)
    DuplicateError(msg) -> LinkerParseError("Duplicate error: " <> msg)
  }
}
