import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/bool
import gleam/list
import gleam/string

/// Returns all linked editing ranges as #(line, col, length) for the symbol
/// under the cursor. Editing any one of these ranges should update all others.
/// Returns an empty list if the cursor is not on a defined symbol.
pub fn get_linked_editing_ranges(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> []
    name -> {
      use <- bool.guard(!file_utils.is_defined_symbol(content, name), [])
      let len = string.length(name)
      position_utils.find_all_name_positions(content, name)
      |> list.map(fn(pos) { #(pos.0, pos.1, len) })
    }
  }
}
