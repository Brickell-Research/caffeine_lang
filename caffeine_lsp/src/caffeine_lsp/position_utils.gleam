import gleam/list
import gleam/string

/// Find the 0-indexed line and column of the first whole-word occurrence
/// of a name in source. Returns #(0, 0) if not found.
pub fn find_name_position(content: String, name: String) -> #(Int, Int) {
  let lines = string.split(content, "\n")
  find_in_lines(lines, name, 0)
}

/// Extract the word under the cursor at the given 0-indexed line and character.
@internal
pub fn extract_word_at(content: String, line: Int, character: Int) -> String {
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
  // Clamp col to valid range
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
      // Check if cursor is on a word character
      case list.drop(graphemes, col) {
        [g, ..] ->
          case is_word_char(g) {
            False -> ""
            True -> {
              // Walk left from col to find word start
              let start = find_word_start(graphemes, col)
              // Walk right from col to find word end
              let end = find_word_end(graphemes, col, len)
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

/// Walk left from col to find the start of the word.
fn find_word_start(graphemes: List(String), col: Int) -> Int {
  find_word_start_loop(graphemes, col, 0, 0)
}

fn find_word_start_loop(
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
          find_word_start_loop(rest, col, idx + 1, new_last)
        }
      }
    }
  }
}

/// Walk right from col to find the end of the word (exclusive).
fn find_word_end(graphemes: List(String), col: Int, len: Int) -> Int {
  find_word_end_loop(graphemes, col, 0, len)
}

fn find_word_end_loop(
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
        False -> find_word_end_loop(rest, col, idx + 1, len)
      }
    }
  }
}

fn find_in_lines(
  lines: List(String),
  name: String,
  line_idx: Int,
) -> #(Int, Int) {
  case lines {
    [] -> #(0, 0)
    [first, ..rest] -> {
      case find_whole_word(first, name, 0) {
        Ok(col) -> #(line_idx, col)
        Error(_) -> find_in_lines(rest, name, line_idx + 1)
      }
    }
  }
}

/// Search for `name` as a whole word within `line`, starting from `offset`.
/// Returns Ok(column) on match, Error(Nil) if not found.
fn find_whole_word(line: String, name: String, offset: Int) -> Result(Int, Nil) {
  case string.split_once(line, name) {
    Error(_) -> Error(Nil)
    Ok(#(before, after)) -> {
      let col = offset + string.length(before)
      let before_ok = case string.last(before) {
        Ok(c) -> !is_word_char(c)
        Error(_) -> True
      }
      let after_ok = case string.first(after) {
        Ok(c) -> !is_word_char(c)
        Error(_) -> True
      }
      case before_ok && after_ok {
        True -> Ok(col)
        False -> {
          // Skip past this match and keep searching
          let skip = string.length(before) + string.length(name)
          find_whole_word(string.drop_start(line, skip), name, offset + skip)
        }
      }
    }
  }
}

fn is_word_char(g: String) -> Bool {
  case g {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "_" -> True
    _ -> False
  }
}
