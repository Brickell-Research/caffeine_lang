/// Source snippet extraction for error display.
/// Extracts lines around an error position and adds line numbers and markers.
import gleam/bool
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
  let start_line = int.max(1, line - 1)
  let end_line = line + 1

  let context = extract_context_lines(source_content, start_line, end_line)

  // Gutter width from actual last line number found.
  let max_line_num = case list.last(context) {
    Ok(#(n, _)) -> n
    Error(_) -> end_line
  }
  let gutter_width = string.length(int.to_string(max_line_num))

  // Extract and format context lines.
  let context_lines =
    context
    |> list.map(fn(pair) {
      format_line(pair.0, pair.1, gutter_width)
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

/// Extracts only the lines in [start_line, end_line] without splitting the entire source.
/// Uses split_once to skip lines before the range and stop after it.
fn extract_context_lines(
  source: String,
  start_line: Int,
  end_line: Int,
) -> List(#(Int, String)) {
  let remaining = skip_lines(source, start_line - 1)
  collect_lines(remaining, start_line, end_line, [])
  |> list.reverse
}

/// Skips past the first `count` lines by splitting on newlines.
fn skip_lines(source: String, count: Int) -> String {
  use <- bool.guard(when: count <= 0, return: source)
  case string.split_once(source, "\n") {
    Ok(#(_, rest)) -> skip_lines(rest, count - 1)
    Error(_) -> source
  }
}

/// Collects lines from current_line to end_line (inclusive).
fn collect_lines(
  source: String,
  current_line: Int,
  end_line: Int,
  acc: List(#(Int, String)),
) -> List(#(Int, String)) {
  use <- bool.guard(when: current_line > end_line, return: acc)
  case string.split_once(source, "\n") {
    Ok(#(line, rest)) ->
      collect_lines(rest, current_line + 1, end_line, [
        #(current_line, line),
        ..acc
      ])
    Error(_) -> {
      // Last line (no trailing newline).
      use <- bool.guard(when: string.is_empty(source), return: acc)
      [#(current_line, source), ..acc]
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
