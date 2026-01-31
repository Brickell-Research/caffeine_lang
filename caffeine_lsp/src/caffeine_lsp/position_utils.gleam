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
      case string.split_once(first, name) {
        Ok(#(before, _)) -> #(line_idx, string.length(before))
        Error(_) -> find_in_lines(rest, name, line_idx + 1)
      }
    }
  }
}
