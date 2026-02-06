import gleam/list
import gleam/string

/// A foldable region defined by start and end lines (0-indexed, inclusive).
pub type FoldingRange {
  FoldingRange(start_line: Int, end_line: Int)
}

/// Compute folding ranges from source content using indentation-based scanning.
pub fn get_folding_ranges(content: String) -> List(FoldingRange) {
  let lines = string.split(content, "\n")
  let indexed = list.index_map(lines, fn(line, idx) { #(idx, line) })
  scan_ranges(indexed, [])
  |> list.reverse
}

fn scan_ranges(
  lines: List(#(Int, String)),
  acc: List(FoldingRange),
) -> List(FoldingRange) {
  case lines {
    [] -> acc
    [#(idx, line), ..rest] -> {
      let trimmed = string.trim_start(line)
      let indent = string.length(line) - string.length(trimmed)
      case is_foldable_start(trimmed, indent) {
        True -> {
          let end = find_block_end(rest, indent)
          case end > idx {
            True -> scan_ranges(rest, [FoldingRange(idx, end), ..acc])
            False -> scan_ranges(rest, acc)
          }
        }
        False -> scan_ranges(rest, acc)
      }
    }
  }
}

/// Check whether a trimmed line at a given indent level starts a foldable block.
fn is_foldable_start(trimmed: String, indent: Int) -> Bool {
  case indent {
    0 ->
      // Top-level: Blueprints/Expectations blocks, extendables, section comments
      string.starts_with(trimmed, "Blueprints ")
      || string.starts_with(trimmed, "Expectations ")
      || string.starts_with(trimmed, "_")
      || string.starts_with(trimmed, "##")
    2 ->
      // Item lines
      string.starts_with(trimmed, "* ")
    4 ->
      // Requires/Provides sections
      string.starts_with(trimmed, "Requires")
      || string.starts_with(trimmed, "Provides")
    _ -> False
  }
}

/// Find the last non-blank line before we hit a sibling or parent indent, or EOF.
fn find_block_end(lines: List(#(Int, String)), parent_indent: Int) -> Int {
  find_block_end_loop(lines, parent_indent, -1)
}

fn find_block_end_loop(
  lines: List(#(Int, String)),
  parent_indent: Int,
  last_non_blank: Int,
) -> Int {
  case lines {
    [] -> last_non_blank
    [#(idx, line), ..rest] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> find_block_end_loop(rest, parent_indent, last_non_blank)
        _ -> {
          let indent =
            string.length(line) - string.length(string.trim_start(line))
          case indent <= parent_indent {
            // Hit a sibling or parent — stop
            True -> last_non_blank
            False -> find_block_end_loop(rest, parent_indent, idx)
          }
        }
      }
    }
  }
}
