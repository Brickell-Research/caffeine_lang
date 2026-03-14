import caffeine_lsp/position_utils
import gleam/bool
import gleam/list
import gleam/string

/// A selection range: the range itself plus an optional parent (wider scope).
pub type SelectionRange {
  SelectionRange(
    start_line: Int,
    start_col: Int,
    end_line: Int,
    end_col: Int,
    parent: SelectionRangeParent,
  )
}

/// Parent of a selection range, or none for the outermost scope.
pub type SelectionRangeParent {
  HasParent(SelectionRange)
  NoParent
}

/// Compute nested selection ranges for the given cursor position.
/// Returns a single SelectionRange with nested parents representing
/// progressively wider scopes: field -> section -> item -> block -> file.
pub fn get_selection_range(
  content: String,
  line: Int,
  _character: Int,
) -> SelectionRange {
  let lines = string.split(content, "\n")
  let total = list.length(lines)

  // Start with the full file as the outermost range
  let file_range =
    SelectionRange(0, 0, total - 1, last_line_length(lines), NoParent)

  // Find enclosing block (Measurements/Expectations or extendable)
  let block_range = find_enclosing_block(lines, line, file_range)

  // Find enclosing item ("name": or * "name":)
  let item_range = find_enclosing_item(lines, line, block_range)

  // Find enclosing section (Requires/Provides)
  let section_range = find_enclosing_section(lines, line, item_range)

  // Innermost: the current line
  let line_len = line_length_at(lines, line)
  let trimmed_start = trimmed_start_col(lines, line)
  SelectionRange(line, trimmed_start, line, line_len, HasParent(section_range))
}

/// Find the enclosing top-level block for the cursor line.
fn find_enclosing_block(
  lines: List(String),
  cursor_line: Int,
  parent: SelectionRange,
) -> SelectionRange {
  let start = find_block_start_loop(lines, cursor_line, 0, -1)
  case start {
    -1 -> parent
    _ -> {
      let remaining = list.drop(lines, start + 1)
      let end = position_utils.find_block_end(remaining, 0, start + 1, start)
      SelectionRange(
        start,
        0,
        end,
        line_length_at(lines, end),
        HasParent(parent),
      )
    }
  }
}

/// Walk forward through lines to find the last block-start at or before cursor.
fn find_block_start_loop(
  remaining: List(String),
  cursor_line: Int,
  idx: Int,
  last_block: Int,
) -> Int {
  use <- bool.guard(idx > cursor_line, last_block)
  case remaining {
    [] -> last_block
    [line, ..rest] -> {
      let trimmed = string.trim_start(line)
      let indent = string.length(line) - string.length(trimmed)
      let is_block =
        indent == 0
        && {
          string.starts_with(trimmed, "Measurements ")
          || string.starts_with(trimmed, "Expectations ")
          || string.starts_with(trimmed, "_")
        }
      case is_block {
        True -> find_block_start_loop(rest, cursor_line, idx + 1, idx)
        False -> find_block_start_loop(rest, cursor_line, idx + 1, last_block)
      }
    }
  }
}

/// Find the enclosing item line for the cursor.
fn find_enclosing_item(
  lines: List(String),
  cursor_line: Int,
  parent: SelectionRange,
) -> SelectionRange {
  let reversed = list.take(lines, cursor_line + 1) |> list.reverse
  let start = find_item_start_loop(reversed, cursor_line)
  case start {
    -1 -> parent
    _ -> {
      let item_indent = trimmed_start_col(lines, start)
      let remaining = list.drop(lines, start + 1)
      let end =
        position_utils.find_block_end(remaining, item_indent, start + 1, start)
      SelectionRange(
        start,
        item_indent,
        end,
        line_length_at(lines, end),
        HasParent(parent),
      )
    }
  }
}

/// Walk backwards (via reversed list) to find the enclosing item start.
/// Matches both measurement items (`"name":` at column 0) and expect items
/// (`* "name":` indented).
fn find_item_start_loop(reversed: List(String), idx: Int) -> Int {
  case reversed {
    [] -> -1
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      use <- bool.guard(is_item_line(line, trimmed), idx)
      find_item_start_loop(rest, idx - 1)
    }
  }
}

/// Find the enclosing Requires/Provides section.
fn find_enclosing_section(
  lines: List(String),
  cursor_line: Int,
  parent: SelectionRange,
) -> SelectionRange {
  let reversed = list.take(lines, cursor_line + 1) |> list.reverse
  let start = find_section_start_loop(reversed, cursor_line)
  case start {
    -1 -> parent
    _ -> {
      let remaining = list.drop(lines, start + 1)
      let end = position_utils.find_block_end(remaining, 4, start + 1, start)
      SelectionRange(
        start,
        trimmed_start_col(lines, start),
        end,
        line_length_at(lines, end),
        HasParent(parent),
      )
    }
  }
}

/// Walk backwards (via reversed list) to find the enclosing section start.
fn find_section_start_loop(reversed: List(String), idx: Int) -> Int {
  case reversed {
    [] -> -1
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      use <- bool.guard(
        string.starts_with(trimmed, "Requires")
          || string.starts_with(trimmed, "Provides"),
        idx,
      )
      use <- bool.guard(is_item_line(line, trimmed), -1)
      find_section_start_loop(rest, idx - 1)
    }
  }
}

fn line_length_at(lines: List(String), idx: Int) -> Int {
  case list.drop(lines, idx) {
    [line, ..] -> string.length(line)
    [] -> 0
  }
}

fn last_line_length(lines: List(String)) -> Int {
  case list.last(lines) {
    Ok(line) -> string.length(line)
    Error(_) -> 0
  }
}

fn trimmed_start_col(lines: List(String), idx: Int) -> Int {
  case list.drop(lines, idx) {
    [line, ..] -> string.length(line) - string.length(string.trim_start(line))
    [] -> 0
  }
}

/// Check whether a line is an item header. Matches both measurement items
/// (`"name":` at column 0) and expect items (`* "name":` indented).
/// Uses the raw line to check indent so quoted field names at deeper
/// indentation are not mistaken for items.
fn is_item_line(raw_line: String, trimmed: String) -> Bool {
  // Expect items: `* "name"` at any indent
  string.starts_with(trimmed, "* \"")
  // Measurement items: `"name"` at column 0 (no indentation)
  || string.starts_with(raw_line, "\"")
}
