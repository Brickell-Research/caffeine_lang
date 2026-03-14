import caffeine_lang/frontend/ast.{
  type ExpectsFile, type MeasurementsFile, type Parsed,
}
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import gleam/string

/// Result of detecting and parsing a caffeine file.
pub type ParsedFile {
  Measurements(MeasurementsFile(Parsed))
  Expects(ExpectsFile(Parsed))
}

/// Check whether a name is likely a user-defined symbol using a fast text scan.
/// Avoids a full parse by checking for definition patterns in the source text.
pub fn is_defined_symbol(content: String, name: String) -> Bool {
  case string.starts_with(name, "_") {
    // Extendables and type aliases start with _ and appear as "_name ("
    True -> string.contains(content, name <> " (")
    // Measurement items appear as "name": at column 0, expect items as * "name":
    False -> string.contains(content, "\"" <> name <> "\"")
  }
}

/// Try to parse content, detecting file type first to avoid double-parsing.
/// Returns the parsed file or both parser error lists.
pub fn parse(
  content: String,
) -> Result(ParsedFile, #(List(ParserError), List(ParserError))) {
  case is_expects_content(content) {
    True ->
      case parser.parse_expects_file(content) {
        Ok(file) -> Ok(Expects(file))
        Error(ex_errs) ->
          case parser.parse_measurements_file(content) {
            Ok(file) -> Ok(Measurements(file))
            Error(bp_errs) -> Error(#(bp_errs, ex_errs))
          }
      }
    False ->
      case parser.parse_measurements_file(content) {
        Ok(file) -> Ok(Measurements(file))
        Error(bp_errs) ->
          case parser.parse_expects_file(content) {
            Ok(file) -> Ok(Expects(file))
            Error(ex_errs) -> Error(#(bp_errs, ex_errs))
          }
      }
  }
}

/// Detect expects file content by scanning for markers unique to expects files.
/// Checks for "Expectations measured by" or "Unmeasured Expectations" which
/// cannot appear in measurement files. Handles expects files that start with
/// extendables, comments, or unmeasured blocks.
fn is_expects_content(content: String) -> Bool {
  string.contains(content, "Expectations measured by")
  || string.contains(content, "Unmeasured Expectations")
}
