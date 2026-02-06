import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/list
import gleam/string

/// Returns all reference locations as #(line, col, length) for the symbol
/// under the cursor. Returns an empty list if the cursor is not on a
/// defined symbol.
pub fn get_references(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> []
    name ->
      case file_utils.is_defined_symbol(content, name) {
        False -> []
        True -> {
          let len = string.length(name)
          position_utils.find_all_name_positions(content, name)
          |> list.map(fn(pos) { #(pos.0, pos.1, len) })
        }
      }
  }
}
