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
  let word = extract_word_at(content, line, character)
  case word {
    "" -> option.None
    name -> find_definition(content, name)
  }
}

/// Look up definition of a name in the parsed file.
/// Supports extendables (_name) and type aliases (_name (Type): ...).
fn find_definition(
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) ->
      find_in_blueprints(file, content, name)
    Ok(file_utils.Expects(file)) ->
      find_in_expects(file, content, name)
    Error(_) -> option.None
  }
}

fn find_in_blueprints(
  file: ast.BlueprintsFile,
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  // Check type aliases
  case list.find(file.type_aliases, fn(ta) { ta.name == name }) {
    Ok(_) -> find_name_location(content, name)
    Error(_) ->
      // Check extendables
      case list.find(file.extendables, fn(e) { e.name == name }) {
        Ok(_) -> find_name_location(content, name)
        Error(_) ->
          // Check blueprint item names
          find_in_blueprint_items(file.blocks, content, name)
      }
  }
}

fn find_in_expects(
  file: ast.ExpectsFile,
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  // Check extendables
  case list.find(file.extendables, fn(e) { e.name == name }) {
    Ok(_) -> find_name_location(content, name)
    Error(_) ->
      // Check expect item names
      find_in_expect_items(file.blocks, content, name)
  }
}

fn find_in_blueprint_items(
  blocks: List(ast.BlueprintsBlock),
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  let items =
    list.flat_map(blocks, fn(b) { b.items })
  case list.find(items, fn(item) { item.name == name }) {
    Ok(_) -> find_name_location(content, name)
    Error(_) -> option.None
  }
}

fn find_in_expect_items(
  blocks: List(ast.ExpectsBlock),
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
  let items =
    list.flat_map(blocks, fn(b) { b.items })
  case list.find(items, fn(item) { item.name == name }) {
    Ok(_) -> find_name_location(content, name)
    Error(_) -> option.None
  }
}

fn find_name_location(
  content: String,
  name: String,
) -> Option(#(Int, Int, Int)) {
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

/// Extract the word under the cursor at the given 0-indexed line and character.
fn extract_word_at(content: String, line: Int, character: Int) -> String {
  case line >= 0 {
    False -> ""
    True -> {
      let lines = string.split(content, "\n")
      case list.drop(lines, line) {
        [line_text, ..] -> word_at_column(line_text, character)
        [] -> ""
      }
    }
  }
}

fn word_at_column(line: String, col: Int) -> String {
  let graphemes = string.to_graphemes(line)
  let len = list.length(graphemes)
  let col = case col < 0 {
    True -> 0
    False ->
      case col >= len {
        True -> len - 1
        False -> col
      }
  }
  case len == 0 {
    True -> ""
    False -> {
      case list.drop(graphemes, col) {
        [g, ..] ->
          case is_word_char(g) {
            False -> ""
            True -> {
              let start = find_word_start(graphemes, col, 0, 0)
              let end = find_word_end(graphemes, col, 0, len)
              graphemes
              |> list.drop(start)
              |> list.take(end - start)
              |> string.join("")
            }
          }
        [] -> ""
      }
    }
  }
}

fn find_word_start(
  graphemes: List(String),
  col: Int,
  idx: Int,
  last_non_word: Int,
) -> Int {
  case graphemes {
    [] -> last_non_word
    [g, ..rest] -> {
      case idx > col {
        True -> last_non_word
        False -> {
          let new_last = case is_word_char(g) {
            True -> last_non_word
            False -> idx + 1
          }
          find_word_start(rest, col, idx + 1, new_last)
        }
      }
    }
  }
}

fn find_word_end(
  graphemes: List(String),
  col: Int,
  idx: Int,
  len: Int,
) -> Int {
  case graphemes {
    [] -> len
    [g, ..rest] -> {
      case idx > col && !is_word_char(g) {
        True -> idx
        False -> find_word_end(rest, col, idx + 1, len)
      }
    }
  }
}

fn is_word_char(g: String) -> Bool {
  case g {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l"
    | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x"
    | "y" | "z"
    -> True
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L"
    | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X"
    | "Y" | "Z"
    -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "_" -> True
    _ -> False
  }
}
