import caffeine_lsp/position_utils

/// Returns highlight locations as #(line, col, length) for the symbol
/// under the cursor. Returns an empty list if the cursor is not on a
/// defined symbol.
pub fn get_highlights(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  position_utils.find_defined_symbol_positions(content, line, character)
}
