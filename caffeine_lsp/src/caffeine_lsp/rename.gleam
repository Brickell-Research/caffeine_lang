import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/bool
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Validate that the cursor is on a renameable symbol and return its range.
/// Returns Some(#(line, col, length)) or None.
pub fn prepare_rename(
  content: String,
  line: Int,
  character: Int,
) -> Option(#(Int, Int, Int)) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> option.None
    name -> {
      use <- bool.guard(
        !file_utils.is_defined_symbol(content, name),
        option.None,
      )
      let len = string.length(name)
      let positions = position_utils.find_all_name_positions(content, name)
      // Find the occurrence that contains the cursor
      list.find(positions, fn(pos) {
        pos.0 == line && character >= pos.1 && character < pos.1 + len
      })
      |> option.from_result
      |> option.map(fn(pos) { #(pos.0, pos.1, len) })
    }
  }
}

/// Return all locations where the symbol should be renamed.
/// Returns #(line, col, length) tuples for every occurrence.
pub fn get_rename_edits(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  position_utils.find_defined_symbol_positions(content, line, character)
}
