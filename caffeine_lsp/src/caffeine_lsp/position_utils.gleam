import caffeine_lsp/file_utils
import gleam/bool
import gleam/list
import gleam/string

/// Find the 0-indexed line and column of the first whole-word occurrence
/// of a name in source, or Error(Nil) if not found.
pub fn find_name_position(
  content: String,
  name: String,
) -> Result(#(Int, Int), Nil) {
  let lines = string.split(content, "\n")
  find_in_lines(lines, name, 0)
}

/// Find the 0-indexed line and column of the first whole-word occurrence
/// of a name in pre-split source lines. Avoids re-splitting the content
/// when called multiple times. Returns Error(Nil) if not found.
@internal
pub fn find_name_position_in_lines(
  lines: List(String),
  name: String,
) -> Result(#(Int, Int), Nil) {
  find_in_lines(lines, name, 0)
}

/// Find the 0-indexed line and column of the first whole-word occurrence
/// of a name, searching only from `start_line` onward. Returns Error(Nil)
/// if not found.
pub fn find_name_position_after_line(
  content: String,
  name: String,
  start_line: Int,
) -> Result(#(Int, Int), Nil) {
  let lines = string.split(content, "\n") |> list.drop(start_line)
  find_in_lines(lines, name, start_line)
}

/// Find the first whole-word occurrence of `name` starting from `from_line`
/// in pre-split `lines`. Avoids re-splitting content on every call.
/// Returns Error(Nil) if not found.
@internal
pub fn find_name_in_lines_from(
  lines: List(String),
  name: String,
  from_line: Int,
) -> Result(#(Int, Int), Nil) {
  find_in_lines(list.drop(lines, from_line), name, from_line)
}

/// Find all 0-indexed (line, col) positions of whole-word occurrences of a name.
pub fn find_all_name_positions(
  content: String,
  name: String,
) -> List(#(Int, Int)) {
  let lines = string.split(content, "\n")
  find_all_in_lines(lines, name, 0, [])
  |> list.reverse
}

/// Extract the word under the cursor at the given 0-indexed line and character.
@internal
pub fn extract_word_at(content: String, line: Int, character: Int) -> String {
  case line >= 0 {
    False -> ""
    True -> {
      let lines = string.split(content, "\n")
      case list.drop(lines, line) {
        [line_text, ..] -> word_at_column(line_text, character)
        [] -> ""
      }
    }
  }
}

fn word_at_column(line: String, col: Int) -> String {
  let graphemes = string.to_graphemes(line)
  let len = list.length(graphemes)
  case len == 0 {
    True -> ""
    False -> {
      // Clamp col to valid range [0, len-1]
      let col = case col < 0 {
        True -> 0
        False ->
          case col >= len {
            True -> len - 1
            False -> col
          }
      }
      // Check if cursor is on a word character
      case list.drop(graphemes, col) {
        [g, ..] ->
          case is_word_char(g) {
            False -> ""
            True -> {
              // Walk left from col to find word start
              let start = find_word_start(graphemes, col)
              // Walk right from col to find word end
              let end = find_word_end(graphemes, col, len)
              graphemes
              |> list.drop(start)
              |> list.take(end - start)
              |> string.join("")
            }
          }
        [] -> ""
      }
    }
  }
}

/// Walk left from col to find the start of the word.
fn find_word_start(graphemes: List(String), col: Int) -> Int {
  find_word_start_loop(graphemes, col, 0, 0)
}

fn find_word_start_loop(
  graphemes: List(String),
  col: Int,
  idx: Int,
  last_non_word: Int,
) -> Int {
  case graphemes {
    [] -> last_non_word
    [g, ..rest] -> {
      case idx > col {
        True -> last_non_word
        False -> {
          let new_last = case is_word_char(g) {
            True -> last_non_word
            False -> idx + 1
          }
          find_word_start_loop(rest, col, idx + 1, new_last)
        }
      }
    }
  }
}

/// Walk right from col to find the end of the word (exclusive).
fn find_word_end(graphemes: List(String), col: Int, len: Int) -> Int {
  find_word_end_loop(graphemes, col, 0, len)
}

fn find_word_end_loop(
  graphemes: List(String),
  col: Int,
  idx: Int,
  len: Int,
) -> Int {
  case graphemes {
    [] -> len
    [g, ..rest] -> {
      case idx > col && !is_word_char(g) {
        True -> idx
        False -> find_word_end_loop(rest, col, idx + 1, len)
      }
    }
  }
}

fn find_all_in_lines(
  lines: List(String),
  name: String,
  line_idx: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case lines {
    [] -> acc
    [first, ..rest] -> {
      let matches = find_all_whole_words(first, name, 0, [])
      let new_acc =
        list.fold(list.reverse(matches), acc, fn(a, col) {
          [#(line_idx, col), ..a]
        })
      find_all_in_lines(rest, name, line_idx + 1, new_acc)
    }
  }
}

fn find_all_whole_words(
  line: String,
  name: String,
  offset: Int,
  acc: List(Int),
) -> List(Int) {
  case find_whole_word(line, name, offset) {
    Error(_) -> list.reverse(acc)
    Ok(col) -> {
      let skip = col - offset + string.length(name)
      let remaining = string.drop_start(line, skip)
      find_all_whole_words(remaining, name, offset + skip, [col, ..acc])
    }
  }
}

fn find_in_lines(
  lines: List(String),
  name: String,
  line_idx: Int,
) -> Result(#(Int, Int), Nil) {
  case lines {
    [] -> Error(Nil)
    [first, ..rest] -> {
      case find_whole_word(first, name, 0) {
        Ok(col) -> Ok(#(line_idx, col))
        Error(_) -> find_in_lines(rest, name, line_idx + 1)
      }
    }
  }
}

/// Search for `name` as a whole word within `line`, starting from `offset`.
/// Returns Ok(column) on match, Error(Nil) if not found.
fn find_whole_word(line: String, name: String, offset: Int) -> Result(Int, Nil) {
  // Guard against empty name: on JS target, split_once("...", "") matches at
  // position 0 with skip=0, causing an infinite loop.
  use <- bool.guard(when: name == "", return: Error(Nil))
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
          find_whole_word(string.drop_start(line, skip), name, offset + skip)
        }
      }
    }
  }
}

/// Find all positions where a string appears inside double quotes.
/// Returns (line, col) of the content start (after the opening quote).
pub fn find_all_quoted_string_positions(
  content: String,
  target: String,
) -> List(#(Int, Int)) {
  let quoted = "\"" <> target <> "\""
  let lines = string.split(content, "\n")
  find_all_quoted_in_lines(lines, quoted, 0, [])
  |> list.reverse
}

fn find_all_quoted_in_lines(
  lines: List(String),
  quoted: String,
  line_idx: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case lines {
    [] -> acc
    [first, ..rest] -> {
      let matches = find_all_quoted_on_line(first, quoted, 0, [])
      let new_acc =
        list.fold(list.reverse(matches), acc, fn(a, col) {
          [#(line_idx, col), ..a]
        })
      find_all_quoted_in_lines(rest, quoted, line_idx + 1, new_acc)
    }
  }
}

fn find_all_quoted_on_line(
  line: String,
  quoted: String,
  offset: Int,
  acc: List(Int),
) -> List(Int) {
  case string.split_once(line, quoted) {
    Error(_) -> list.reverse(acc)
    Ok(#(before, after)) -> {
      // +1 for the opening quote — position of the content itself
      let col = offset + string.length(before) + 1
      let new_offset = offset + string.length(before) + string.length(quoted)
      find_all_quoted_on_line(after, quoted, new_offset, [col, ..acc])
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

/// Find all positions of a defined symbol under the cursor.
/// Returns #(line, col, length) for each occurrence, or an empty list
/// if the cursor is not on a defined symbol.
pub fn find_defined_symbol_positions(
  content: String,
  line: Int,
  character: Int,
) -> List(#(Int, Int, Int)) {
  let word = extract_word_at(content, line, character)
  case word {
    "" -> []
    name -> {
      use <- bool.guard(!file_utils.is_defined_symbol(content, name), [])
      let len = string.length(name)
      find_all_name_positions(content, name)
      |> list.map(fn(pos) { #(pos.0, pos.1, len) })
    }
  }
}

/// Find the last non-blank line before a sibling or parent indent level.
/// `lines` should start after the block header; `start_idx` is the 0-indexed
/// line number of the first element. Returns `fallback` if no content found.
@internal
pub fn find_block_end(
  lines: List(String),
  parent_indent: Int,
  start_idx: Int,
  fallback: Int,
) -> Int {
  find_block_end_loop(lines, parent_indent, start_idx, fallback)
}

fn find_block_end_loop(
  lines: List(String),
  parent_indent: Int,
  idx: Int,
  last_non_blank: Int,
) -> Int {
  case lines {
    [] -> last_non_blank
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> find_block_end_loop(rest, parent_indent, idx + 1, last_non_blank)
        _ -> {
          let indent =
            string.length(line) - string.length(string.trim_start(line))
          use <- bool.guard(indent <= parent_indent, last_non_blank)
          find_block_end_loop(rest, parent_indent, idx + 1, idx)
        }
      }
    }
  }
}

/// Find the 0-indexed line number where an item named `item_name` appears.
/// Matches both measurement items (`"name":` at column 0) and expect items
/// (`* "name":` with indentation). Returns `fallback` if not found.
@internal
pub fn find_item_start_line(
  lines: List(String),
  item_name: String,
  fallback: Int,
) -> Int {
  let measurement_pattern = "\"" <> item_name <> "\""
  let expect_pattern = "* \"" <> item_name <> "\""
  find_item_start_line_loop(
    lines,
    measurement_pattern,
    expect_pattern,
    0,
    fallback,
  )
}

/// Find the 0-indexed line number where an item named `item_name` appears,
/// starting the search from `from_line`. Returns `fallback` if not found.
@internal
pub fn find_item_start_line_from(
  lines: List(String),
  item_name: String,
  from_line: Int,
  fallback: Int,
) -> Int {
  let measurement_pattern = "\"" <> item_name <> "\""
  let expect_pattern = "* \"" <> item_name <> "\""
  find_item_start_line_loop(
    list.drop(lines, from_line),
    measurement_pattern,
    expect_pattern,
    from_line,
    fallback,
  )
}

fn find_item_start_line_loop(
  lines: List(String),
  measurement_pattern: String,
  expect_pattern: String,
  idx: Int,
  fallback: Int,
) -> Int {
  case lines {
    [] -> fallback
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case
        string.starts_with(trimmed, measurement_pattern)
        || string.starts_with(trimmed, expect_pattern)
      {
        True -> idx
        False ->
          find_item_start_line_loop(
            rest,
            measurement_pattern,
            expect_pattern,
            idx + 1,
            fallback,
          )
      }
    }
  }
}
