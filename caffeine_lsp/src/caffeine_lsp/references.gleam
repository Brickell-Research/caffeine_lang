import caffeine_lsp/definition
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/bool
import gleam/list
import gleam/option
import gleam/string

/// Returns all reference locations as #(line, col, length) for the symbol
/// under the cursor. Returns an empty list if the cursor is not on a
/// defined symbol or blueprint name.
pub fn get_references(
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
    option.None -> {
      // Fall back to word-based symbol references
      let word = position_utils.extract_word_at(content, line, character)
      case word {
        "" -> []
        name -> {
          let is_symbol = file_utils.is_defined_symbol(content, name)
          let is_blueprint = is_blueprint_name(content, name)
          use <- bool.guard(!is_symbol && !is_blueprint, [])
          let len = string.length(name)
          position_utils.find_all_name_positions(content, name)
          |> list.map(fn(pos) { #(pos.0, pos.1, len) })
        }
      }
    }
  }
}

/// Returns the blueprint name at the cursor position if it represents a
/// cross-file referable name, or an empty string otherwise.
@internal
pub fn get_blueprint_name_at(
  content: String,
  line: Int,
  character: Int,
) -> String {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> ""
    name -> {
      use <- bool.guard(!is_blueprint_name(content, name), "")
      name
    }
  }
}

/// Finds all positions where a name appears as a whole word in content.
/// Returns #(line, col, length) tuples for cross-file reference searching.
pub fn find_references_to_name(
  content: String,
  name: String,
) -> List(#(Int, Int, Int)) {
  let len = string.length(name)
  position_utils.find_all_name_positions(content, name)
  |> list.map(fn(pos) { #(pos.0, pos.1, len) })
}

/// Check whether a name appears in a blueprint-relevant quoted context.
fn is_blueprint_name(content: String, name: String) -> Bool {
  string.contains(content, "* \"" <> name <> "\"")
  || string.contains(content, "for \"" <> name <> "\"")
}
