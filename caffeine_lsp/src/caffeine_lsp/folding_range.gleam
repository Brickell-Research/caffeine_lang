import caffeine_lsp/position_utils
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
        False -> scan_ranges(rest, acc)
        True -> {
          let end = find_block_end(rest, indent)
          case end <= idx {
            True -> scan_ranges(rest, acc)
            False -> scan_ranges(rest, [FoldingRange(idx, end), ..acc])
          }
        }
      }
    }
  }
}

/// Check whether a trimmed line at a given indent level starts a foldable block.
fn is_foldable_start(trimmed: String, indent: Int) -> Bool {
  case indent {
    0 ->
      // Top-level: Measurements/Expectations blocks, extendables, section comments,
      // and measurement items ("name":)
      string.starts_with(trimmed, "Measurements ")
      || string.starts_with(trimmed, "Expectations ")
      || string.starts_with(trimmed, "_")
      || string.starts_with(trimmed, "##")
      || string.starts_with(trimmed, "\"")
    2 ->
      // Expect item lines
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
  let plain_lines = list.map(lines, fn(pair) { pair.1 })
  let start_idx = case lines {
    [#(idx, _), ..] -> idx
    [] -> 0
  }
  position_utils.find_block_end(plain_lines, parent_indent, start_idx, -1)
}
