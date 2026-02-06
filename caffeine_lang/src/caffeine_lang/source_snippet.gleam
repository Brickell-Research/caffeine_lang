/// Source snippet extraction for error display.
/// Extracts lines around an error position and adds line numbers and markers.
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// A rendered source snippet with line numbers and error markers.
pub type SourceSnippet {
  SourceSnippet(rendered: String)
}

/// Extracts a source snippet around the given line/column position.
/// Shows 1 line of context above and below the error line.
/// Adds a caret (^) marker under the error position.
/// Line and column are 1-indexed.
pub fn extract_snippet(
  source_content: String,
  line: Int,
  column: Int,
  end_column: Option(Int),
) -> SourceSnippet {
  let lines = string.split(source_content, "\n")
  let total_lines = list.length(lines)

  // Context window: 1 line above and below.
  let start_line = int.max(1, line - 1)
  let end_line = int.min(total_lines, line + 1)

  // Gutter width from largest line number.
  let gutter_width = string.length(int.to_string(end_line))

  // Extract and format context lines.
  let context_lines =
    extract_lines(lines, start_line, end_line)
    |> list.map(fn(pair) {
      let #(line_num, line_content) = pair
      format_line(line_num, line_content, gutter_width)
    })

  // Build marker line.
  let span_width = case end_column {
    option.Some(end_col) -> int.max(1, end_col - column)
    option.None -> 1
  }
  let marker_line = format_marker(column, span_width, gutter_width)

  // Insert marker after the error line.
  let rendered =
    insert_marker(context_lines, line, start_line, marker_line)
    |> string.join("\n")

  SourceSnippet(rendered:)
}

/// Extracts lines from start_line to end_line (1-indexed, inclusive).
fn extract_lines(
  lines: List(String),
  start_line: Int,
  end_line: Int,
) -> List(#(Int, String)) {
  extract_lines_loop(lines, 1, start_line, end_line, [])
  |> list.reverse
}

fn extract_lines_loop(
  lines: List(String),
  current: Int,
  start: Int,
  end: Int,
  acc: List(#(Int, String)),
) -> List(#(Int, String)) {
  case lines {
    [] -> acc
    [line, ..rest] -> {
      case current > end {
        True -> acc
        False -> {
          let new_acc = case current >= start {
            True -> [#(current, line), ..acc]
            False -> acc
          }
          extract_lines_loop(rest, current + 1, start, end, new_acc)
        }
      }
    }
  }
}

/// Formats a single line with its line number gutter.
fn format_line(line_num: Int, content: String, gutter_width: Int) -> String {
  let num_str = int.to_string(line_num)
  let padding = string.repeat(" ", gutter_width - string.length(num_str))
  padding <> num_str <> " | " <> content
}

/// Formats the marker line with carets under the error position.
fn format_marker(column: Int, span_width: Int, gutter_width: Int) -> String {
  let gutter_space = string.repeat(" ", gutter_width)
  let col_space = string.repeat(" ", int.max(0, column - 1))
  let carets = string.repeat("^", span_width)
  gutter_space <> " | " <> col_space <> carets
}

/// Inserts the marker line after the error line in the context.
fn insert_marker(
  context_lines: List(String),
  error_line: Int,
  start_line: Int,
  marker_line: String,
) -> List(String) {
  insert_marker_loop(context_lines, error_line - start_line, marker_line, 0, [])
  |> list.reverse
}

fn insert_marker_loop(
  lines: List(String),
  error_index: Int,
  marker: String,
  current: Int,
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> acc
    [line, ..rest] -> {
      let new_acc = case current == error_index {
        True -> [marker, line, ..acc]
        False -> [line, ..acc]
      }
      insert_marker_loop(rest, error_index, marker, current + 1, new_acc)
    }
  }
}
