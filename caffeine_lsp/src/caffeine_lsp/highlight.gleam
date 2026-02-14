import caffeine_lsp/definition
import caffeine_lsp/position_utils
import gleam/list
import gleam/option
import gleam/string

/// Returns highlight locations as #(line, col, length) for the symbol
/// under the cursor. Returns an empty list if the cursor is not on a
/// defined symbol.
pub fn get_highlights(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  // First: try relation ref (dotted identifiers inside quotes)
  case definition.get_relation_ref_at_position(content, line, character) {
    option.Some(ref) -> {
      let len = string.length(ref)
      position_utils.find_all_quoted_string_positions(content, ref)
      |> list.map(fn(pos) { #(pos.0, pos.1, len) })
    }
    option.None ->
      // Fall back to word-based symbol highlights
      position_utils.find_defined_symbol_positions(content, line, character)
  }
}
