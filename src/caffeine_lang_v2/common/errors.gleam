import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/string

// =============================================================================
// Parse Errors
// =============================================================================

/// Represents errors that can occur during the parsing phase of compilation.
pub type ParseError {
  FileReadError(msg: String)
  JsonParserError(msg: String)
  DuplicateError(msg: String)
}

// =============================================================================
// Linker Errors
// =============================================================================

/// Represents errors that can occur during the linking phase of compilation.
pub type LinkerError {
  LinkerParseError(msg: String)
  LinkerSemanticError(msg: String)
}

// =============================================================================
// Semantic / Middle-End Errors
// =============================================================================

/// Represents errors that can occur during semantic analysis.
pub type SemanticError {
  QueryResolutionError(msg: String)
}

/// Represents errors that can occur during CQL query resolution.
pub type ResolveError {
  CqlParseError(msg: String)
  CqlResolveError(msg: String)
  MissingQueryKey(key: String)
}

/// Format a resolve error as a string.
pub fn format_resolve_error(error: ResolveError) -> String {
  case error {
    CqlParseError(msg) -> "CQL parse error: " <> msg
    CqlResolveError(msg) -> "CQL resolve error: " <> msg
    MissingQueryKey(key) -> "Missing query key: " <> key
  }
}

/// Represents errors that can occur during template variable processing.
pub type TemplateError {
  InvalidVariableFormat(variable: String)
  MissingAttribute(attribute: String)
  UnterminatedVariable(partial: String)
}

/// Format a template error as a string.
pub fn format_template_error(error: TemplateError) -> String {
  case error {
    InvalidVariableFormat(var) -> "Invalid template variable format: " <> var
    MissingAttribute(attr) -> "Missing template attribute: " <> attr
    UnterminatedVariable(partial) ->
      "Unterminated template variable: $$" <> partial
  }
}

// =============================================================================
// Generator Errors
// =============================================================================

/// Represents errors that can occur during code generation.
pub type GeneratorError {
  MissingValue(key: String)
  TypeError(key: String, expected: String, found: String)
  InvalidArtifact(artifact_ref: String)
  RenderError(msg: String)
}

/// Format a generator error as a string.
pub fn format_generator_error(error: GeneratorError) -> String {
  case error {
    MissingValue(key) -> "Missing required value: " <> key
    TypeError(key, expected, found) ->
      "Type error for '"
      <> key
      <> "': expected "
      <> expected
      <> ", found "
      <> found
    InvalidArtifact(artifact_ref) -> "Unknown artifact type: " <> artifact_ref
    RenderError(msg) -> "Render error: " <> msg
  }
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
