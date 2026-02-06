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

  // Find enclosing block (Blueprints/Expectations or extendable)
  let block_range = find_enclosing_block(lines, line, file_range)

  // Find enclosing item (* "name":)
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
  let result = find_block_start_loop(lines, cursor_line, 0, -1)
  case result {
    -1 -> parent
    start -> {
      let end = find_block_end(lines, start)
      SelectionRange(start, 0, end, line_length_at(lines, end), HasParent(parent))
    }
  }
}

fn find_block_start_loop(
  lines: List(String),
  cursor_line: Int,
  idx: Int,
  last_block: Int,
) -> Int {
  use <- bool.guard(idx > cursor_line, last_block)
  case list.drop(lines, idx) {
    [] -> last_block
    [line, ..] -> {
      let trimmed = string.trim_start(line)
      let indent = string.length(line) - string.length(trimmed)
      let is_block =
        indent == 0
        && {
          string.starts_with(trimmed, "Blueprints ")
          || string.starts_with(trimmed, "Expectations ")
          || string.starts_with(trimmed, "_")
        }
      use <- bool.guard(
        is_block,
        find_block_start_loop(lines, cursor_line, idx + 1, idx),
      )
      find_block_start_loop(lines, cursor_line, idx + 1, last_block)
    }
  }
}

/// Find the enclosing item line for the cursor.
fn find_enclosing_item(
  lines: List(String),
  cursor_line: Int,
  parent: SelectionRange,
) -> SelectionRange {
  let result = find_item_start_loop(lines, cursor_line)
  case result {
    -1 -> parent
    start -> {
      let end = find_item_end(lines, start, list.length(lines))
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

fn find_item_start_loop(lines: List(String), idx: Int) -> Int {
  use <- bool.guard(idx < 0, -1)
  case list.drop(lines, idx) {
    [] -> -1
    [line, ..] -> {
      let trimmed = string.trim(line)
      use <- bool.guard(string.starts_with(trimmed, "* \""), idx)
      find_item_start_loop(lines, idx - 1)
    }
  }
}

fn find_item_end(lines: List(String), start: Int, total: Int) -> Int {
  find_item_end_loop(lines, start + 1, start, total)
}

fn find_item_end_loop(
  lines: List(String),
  idx: Int,
  last_non_blank: Int,
  total: Int,
) -> Int {
  use <- bool.guard(idx >= total, last_non_blank)
  case list.drop(lines, idx) {
    [] -> last_non_blank
    [line, ..] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> find_item_end_loop(lines, idx + 1, last_non_blank, total)
        _ -> {
          let indent =
            string.length(line) - string.length(string.trim_start(line))
          use <- bool.guard(indent <= 2, last_non_blank)
          find_item_end_loop(lines, idx + 1, idx, total)
        }
      }
    }
  }
}

/// Find the enclosing Requires/Provides section.
fn find_enclosing_section(
  lines: List(String),
  cursor_line: Int,
  parent: SelectionRange,
) -> SelectionRange {
  let result = find_section_start_loop(lines, cursor_line)
  case result {
    -1 -> parent
    start -> {
      let end = find_section_end(lines, start, list.length(lines))
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

fn find_section_start_loop(lines: List(String), idx: Int) -> Int {
  use <- bool.guard(idx < 0, -1)
  case list.drop(lines, idx) {
    [] -> -1
    [line, ..] -> {
      let trimmed = string.trim(line)
      use <- bool.guard(
        string.starts_with(trimmed, "Requires")
          || string.starts_with(trimmed, "Provides"),
        idx,
      )
      use <- bool.guard(string.starts_with(trimmed, "* \""), -1)
      find_section_start_loop(lines, idx - 1)
    }
  }
}

fn find_section_end(lines: List(String), start: Int, total: Int) -> Int {
  find_section_end_loop(lines, start + 1, start, total)
}

fn find_section_end_loop(
  lines: List(String),
  idx: Int,
  last_non_blank: Int,
  total: Int,
) -> Int {
  use <- bool.guard(idx >= total, last_non_blank)
  case list.drop(lines, idx) {
    [] -> last_non_blank
    [line, ..] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> find_section_end_loop(lines, idx + 1, last_non_blank, total)
        _ -> {
          let indent =
            string.length(line) - string.length(string.trim_start(line))
          use <- bool.guard(indent <= 4, last_non_blank)
          find_section_end_loop(lines, idx + 1, idx, total)
        }
      }
    }
  }
}

fn find_block_end(lines: List(String), start: Int) -> Int {
  let total = list.length(lines)
  find_block_end_loop(lines, start + 1, start, total)
}

fn find_block_end_loop(
  lines: List(String),
  idx: Int,
  last_non_blank: Int,
  total: Int,
) -> Int {
  use <- bool.guard(idx >= total, last_non_blank)
  case list.drop(lines, idx) {
    [] -> last_non_blank
    [line, ..] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> find_block_end_loop(lines, idx + 1, last_non_blank, total)
        _ -> {
          let indent =
            string.length(line) - string.length(string.trim_start(line))
          use <- bool.guard(indent == 0, last_non_blank)
          find_block_end_loop(lines, idx + 1, idx, total)
        }
      }
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
