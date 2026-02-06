import caffeine_lang/frontend/ast.{type BlueprintsFile, type ExpectsFile}
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import gleam/string

/// Result of detecting and parsing a caffeine file.
pub type ParsedFile {
  Blueprints(BlueprintsFile)
  Expects(ExpectsFile)
}

/// Check whether a name is likely a user-defined symbol using a fast text scan.
/// Avoids a full parse by checking for definition patterns in the source text.
pub fn is_defined_symbol(content: String, name: String) -> Bool {
  case string.starts_with(name, "_") {
    // Extendables and type aliases start with _ and appear as "_name ("
    True -> string.contains(content, name <> " (")
    // Item names appear as * "name"
    False -> string.contains(content, "* \"" <> name <> "\"")
  }
}

/// Try to parse content, detecting file type first to avoid double-parsing.
/// Returns the parsed file or both parser errors.
pub fn parse(content: String) -> Result(ParsedFile, #(ParserError, ParserError)) {
  case string.starts_with(string.trim_start(content), "Expectations") {
    True ->
      case parser.parse_expects_file(content) {
        Ok(file) -> Ok(Expects(file))
        Error(ex_err) ->
          case parser.parse_blueprints_file(content) {
            Ok(file) -> Ok(Blueprints(file))
            Error(bp_err) -> Error(#(bp_err, ex_err))
          }
      }
    False ->
      case parser.parse_blueprints_file(content) {
        Ok(file) -> Ok(Blueprints(file))
        Error(bp_err) ->
          case parser.parse_expects_file(content) {
            Ok(file) -> Ok(Expects(file))
            Error(ex_err) -> Error(#(bp_err, ex_err))
          }
      }
  }
}

