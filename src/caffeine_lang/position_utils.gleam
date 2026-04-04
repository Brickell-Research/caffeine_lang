/// Utilities for finding source positions of names in content.
/// Positions are 1-indexed to match parser/tokenizer conventions.
import gleam/string

/// Finds the 1-indexed line and column of the first whole-word occurrence
/// of a name in source. Returns #(1, 1) if not found.
pub fn find_name_position(content: String, name: String) -> #(Int, Int) {
  let lines = string.split(content, "\n")
  find_in_lines(lines, name, 1)
}

fn find_in_lines(
  lines: List(String),
  name: String,
  line_num: Int,
) -> #(Int, Int) {
  case lines {
    [] -> #(1, 1)
    [first, ..rest] -> {
      case find_whole_word(first, name, 0) {
        Ok(col) -> #(line_num, col + 1)
        Error(_) -> find_in_lines(rest, name, line_num + 1)
      }
    }
  }
}

/// Searches for `name` as a whole word within `line`, starting from `offset`.
/// Returns Ok(column) as 0-indexed offset on match, Error(Nil) if not found.
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
          let skip = string.length(before) + string.length(name)
          find_whole_word(string.drop_start(line, skip), name, offset + skip)
        }
      }
    }
  }
}

fn is_word_char(g: String) -> Bool {
  case g {
    "_" -> True
    _ ->
      case string.to_utf_codepoints(g) {
        [cp] -> {
          let code = string.utf_codepoint_to_int(cp)
          { code >= 65 && code <= 90 }
          || { code >= 97 && code <= 122 }
          || { code >= 48 && code <= 57 }
        }
        _ -> False
      }
  }
}
