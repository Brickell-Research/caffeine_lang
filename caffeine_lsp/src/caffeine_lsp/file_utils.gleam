import caffeine_lang/frontend/ast.{type BlueprintsFile, type ExpectsFile}
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import gleam/list
import gleam/string

/// Result of detecting and parsing a caffeine file.
pub type ParsedFile {
  Blueprints(BlueprintsFile)
  Expects(ExpectsFile)
}

/// Check whether a name is a user-defined symbol in the parsed file.
pub fn is_defined_symbol(content: String, name: String) -> Bool {
  case parse(content) {
    Ok(Blueprints(file)) -> is_blueprints_symbol(file, name)
    Ok(Expects(file)) -> is_expects_symbol(file, name)
    Error(_) -> False
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

fn is_blueprints_symbol(file: BlueprintsFile, name: String) -> Bool {
  let all_names =
    list.flatten([
      list.map(file.type_aliases, fn(ta) { ta.name }),
      list.map(file.extendables, fn(e) { e.name }),
      list.flat_map(file.blocks, fn(b) {
        list.map(b.items, fn(item) { item.name })
      }),
    ])
  list.any(all_names, fn(n) { n == name })
}

fn is_expects_symbol(file: ExpectsFile, name: String) -> Bool {
  let all_names =
    list.flatten([
      list.map(file.extendables, fn(e) { e.name }),
      list.flat_map(file.blocks, fn(b) {
        list.map(b.items, fn(item) { item.name })
      }),
    ])
  list.any(all_names, fn(n) { n == name })
}
