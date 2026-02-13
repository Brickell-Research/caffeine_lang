import caffeine_lang/frontend/ast.{type ExpectsBlock}
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/bool
import gleam/list
import gleam/option.{type Option}
import gleam/result
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

/// Returns the blueprint name if the cursor is on a blueprint reference
/// in an `Expectations for "name"` header, or None otherwise.
pub fn get_blueprint_ref_at_position(
  content: String,
  line: Int,
  character: Int,
) -> Option(String) {
  case file_utils.parse(content) {
    Ok(file_utils.Expects(file)) -> {
      let lines = string.split(content, "\n")
      case list.drop(lines, line) {
        [line_text, ..] ->
          find_blueprint_ref_on_line(line_text, character, file.blocks)
        [] -> option.None
      }
    }
    _ -> option.None
  }
}

/// Returns the dotted identifier if the cursor is on a dependency relation
/// string (e.g., "org.team.service.name"), or None otherwise.
pub fn get_relation_ref_at_position(
  content: String,
  line: Int,
  character: Int,
) -> Option(String) {
  let lines = string.split(content, "\n")
  case list.drop(lines, line) {
    [line_text, ..] -> extract_dependency_ref_on_line(line_text, character)
    [] -> option.None
  }
}

/// Extract a dependency path string if the cursor is inside a quoted string
/// that matches the org.team.service.name pattern.
fn extract_dependency_ref_on_line(
  line_text: String,
  character: Int,
) -> Option(String) {
  let parts = string.split(line_text, "\"")
  scan_string_parts(parts, 0, 0, character)
}

fn scan_string_parts(
  parts: List(String),
  part_idx: Int,
  pos: Int,
  target: Int,
) -> Option(String) {
  case parts {
    [] -> option.None
    [part, ..rest] -> {
      let part_len = string.length(part)
      let end_pos = pos + part_len
      // Odd-indexed parts (1, 3, 5, ...) are inside quote pairs
      let is_string_content = part_idx % 2 == 1
      case is_string_content && target >= pos && target < end_pos {
        True -> {
          case is_dependency_path(part) {
            True -> option.Some(part)
            False -> option.None
          }
        }
        // +1 to skip the quote separator between parts
        False -> scan_string_parts(rest, part_idx + 1, end_pos + 1, target)
      }
    }
  }
}

/// Check if a string looks like a dependency path (exactly 4 non-empty
/// dot-separated segments).
fn is_dependency_path(s: String) -> Bool {
  case string.split(s, ".") {
    [a, b, c, d] -> a != "" && b != "" && c != "" && d != ""
    _ -> False
  }
}

/// Check if the cursor is on a blueprint name within an Expectations header.
fn find_blueprint_ref_on_line(
  line_text: String,
  character: Int,
  blocks: List(ExpectsBlock),
) -> Option(String) {
  let prefix = "Expectations for \""
  use <- bool.guard(!string.contains(line_text, prefix), option.None)
  list.find_map(blocks, fn(block) {
    let pattern = prefix <> block.blueprint <> "\""
    use <- bool.guard(!string.contains(line_text, pattern), Error(Nil))
    case string.split_once(line_text, prefix) {
      Error(_) -> Error(Nil)
      Ok(#(before, _)) -> {
        let name_start = string.length(before) + string.length(prefix)
        let name_end = name_start + string.length(block.blueprint)
        case character >= name_start && character < name_end {
          True -> Ok(block.blueprint)
          False -> Error(Nil)
        }
      }
    }
  })
  |> result.replace_error(Nil)
  |> option.from_result
}
