import caffeine_lang/frontend/ast.{
  type BlueprintsFile, type ExpectsFile, type Parsed,
}
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import gleam/string

/// Result of detecting and parsing a caffeine file.
pub type ParsedFile {
  Blueprints(BlueprintsFile(Parsed))
  Expects(ExpectsFile(Parsed))
}

/// Check whether a name is likely a user-defined symbol using a fast text scan.
/// Avoids a full parse by checking for definition patterns in the source text.
pub fn is_defined_symbol(content: String, name: String) -> Bool {
  case string.starts_with(name, "_") {
    // Extendables and type aliases start with _ and appear as "_name ("
    True -> string.contains(content, name <> " (")
    // Blueprint items appear as "name": at column 0, expect items as * "name":
    False -> string.contains(content, "\"" <> name <> "\"")
  }
}

/// Try to parse content, detecting file type first to avoid double-parsing.
/// Returns the parsed file or both parser error lists.
pub fn parse(
  content: String,
) -> Result(ParsedFile, #(List(ParserError), List(ParserError))) {
  case string.starts_with(string.trim_start(content), "Expectations") {
    True ->
      case parser.parse_expects_file(content) {
        Ok(file) -> Ok(Expects(file))
        Error(ex_errs) ->
          case parser.parse_blueprints_file(content) {
            Ok(file) -> Ok(Blueprints(file))
            Error(bp_errs) -> Error(#(bp_errs, ex_errs))
          }
      }
    False ->
      case parser.parse_blueprints_file(content) {
        Ok(file) -> Ok(Blueprints(file))
        Error(bp_errs) ->
          case parser.parse_expects_file(content) {
            Ok(file) -> Ok(Expects(file))
            Error(ex_errs) -> Error(#(bp_errs, ex_errs))
          }
      }
  }
}
