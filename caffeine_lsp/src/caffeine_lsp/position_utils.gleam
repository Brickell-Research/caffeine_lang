import gleam/string

/// Find the 0-indexed line and column of the first occurrence of a name in source.
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
      case string.contains(first, name) {
        True -> {
          let col = find_column(first, name, 0)
          #(line_idx, col)
        }
        False -> find_in_lines(rest, name, line_idx + 1)
      }
    }
  }
}

fn find_column(line: String, name: String, offset: Int) -> Int {
  case string.starts_with(line, name) {
    True -> offset
    False -> {
      case string.pop_grapheme(line) {
        Ok(#(_, rest)) -> find_column(rest, name, offset + 1)
        Error(_) -> 0
      }
    }
  }
}
