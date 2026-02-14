import caffeine_lsp/position_utils

/// Returns all linked editing ranges as #(line, col, length) for the symbol
/// under the cursor. Editing any one of these ranges should update all others.
/// Returns an empty list if the cursor is not on a defined symbol.
pub fn get_linked_editing_ranges(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  position_utils.find_defined_symbol_positions(content, line, character)
}
