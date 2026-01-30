import caffeine_lang/frontend/ast.{type BlueprintsFile, type ExpectsFile}
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}

/// Result of detecting and parsing a caffeine file.
pub type ParsedFile {
  Blueprints(BlueprintsFile)
  Expects(ExpectsFile)
}

/// Try to parse content as a blueprints file, then as an expects file.
/// Returns the parsed file or both parser errors.
pub fn parse(
  content: String,
) -> Result(ParsedFile, #(ParserError, ParserError)) {
  case parser.parse_blueprints_file(content) {
    Ok(file) -> Ok(Blueprints(file))
    Error(bp_err) ->
      case parser.parse_expects_file(content) {
        Ok(file) -> Ok(Expects(file))
        Error(ex_err) -> Error(#(bp_err, ex_err))
      }
  }
}
