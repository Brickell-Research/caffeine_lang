import gleam/string

/// Find the 0-indexed line and column of the first whole-word occurrence
/// of a name in source. Returns #(0, 0) if not found.
pub fn find_name_position(content: String, name: String) -> #(Int, Int) {
  let lines = string.split(content, "\n")
  find_in_lines(lines, name, 0)
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
          find_whole_word(
            string.drop_start(line, skip),
            name,
            offset + skip,
          )
        }
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
