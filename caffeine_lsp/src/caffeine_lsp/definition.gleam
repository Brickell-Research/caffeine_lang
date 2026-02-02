import caffeine_lang/frontend/ast
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Returns the definition location (line, col, name_length) for the symbol
/// at the given cursor position, or None if not found.
pub fn get_definition(
  content: String,
  line: Int,
  character: Int,
) -> Option(#(Int, Int, Int)) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> option.None
    name -> find_definition(content, name)
  }
}

/// Look up definition of a name in the parsed file.
/// Supports extendables (_name) and type aliases (_name (Type): ...).
fn find_definition(content: String, name: String) -> Option(#(Int, Int, Int)) {
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> find_in_blueprints(file, content, name)
    Ok(file_utils.Expects(file)) -> find_in_expects(file, content, name)
    Error(_) -> option.None
  }
}

fn find_in_blueprints(
  file: ast.BlueprintsFile,
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  // Check type aliases, extendables, then blueprint items
  let all_names =
    list.flatten([
      list.map(file.type_aliases, fn(ta) { ta.name }),
      list.map(file.extendables, fn(e) { e.name }),
      list.flat_map(file.blocks, fn(b) {
        list.map(b.items, fn(item) { item.name })
      }),
    ])
  case list.find(all_names, fn(n) { n == name }) {
    Ok(_) -> find_name_location(content, name)
    Error(_) -> option.None
  }
}

fn find_in_expects(
  file: ast.ExpectsFile,
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  // Check extendables, then expect items
  let all_names =
    list.flatten([
      list.map(file.extendables, fn(e) { e.name }),
      list.flat_map(file.blocks, fn(b) {
        list.map(b.items, fn(item) { item.name })
      }),
    ])
  case list.find(all_names, fn(n) { n == name }) {
    Ok(_) -> find_name_location(content, name)
    Error(_) -> option.None
  }
}

fn find_name_location(content: String, name: String) -> Option(#(Int, Int, Int)) {
  let #(line, col) = position_utils.find_name_position(content, name)
  case line == 0 && col == 0 {
    // Could be genuinely at 0,0 or not found — check if name is actually there
    True -> {
      case string.starts_with(content, name) {
        True -> option.Some(#(0, 0, string.length(name)))
        False -> option.None
      }
    }
    False -> option.Some(#(line, col, string.length(name)))
  }
}
