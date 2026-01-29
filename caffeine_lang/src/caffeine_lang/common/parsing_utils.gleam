import gleam/list
import gleam/string

/// Splits a string at commas that are not inside parentheses or curly braces.
/// Used by collection and modifier type parsers for nested type arguments.
@internal
pub fn split_at_top_level_comma(s: String) -> List(String) {
  let chars = string.to_graphemes(s)
  do_split_at_top_level_comma(chars, 0, 0, "", [])
}

fn do_split_at_top_level_comma(
  chars: List(String),
  paren_depth: Int,
  brace_depth: Int,
  current: String,
  acc: List(String),
) -> List(String) {
  case chars {
    [] -> {
      let trimmed = string.trim(current)
      case trimmed {
        "" -> list.reverse(acc)
        _ -> list.reverse([trimmed, ..acc])
      }
    }
    ["(", ..rest] ->
      do_split_at_top_level_comma(
        rest,
        paren_depth + 1,
        brace_depth,
        current <> "(",
        acc,
      )
    [")", ..rest] ->
      do_split_at_top_level_comma(
        rest,
        paren_depth - 1,
        brace_depth,
        current <> ")",
        acc,
      )
    ["{", ..rest] ->
      do_split_at_top_level_comma(
        rest,
        paren_depth,
        brace_depth + 1,
        current <> "{",
        acc,
      )
    ["}", ..rest] ->
      do_split_at_top_level_comma(
        rest,
        paren_depth,
        brace_depth - 1,
        current <> "}",
        acc,
      )
    [",", ..rest] if paren_depth == 0 && brace_depth == 0 -> {
      let trimmed = string.trim(current)
      do_split_at_top_level_comma(rest, paren_depth, brace_depth, "", [
        trimmed,
        ..acc
      ])
    }
    [char, ..rest] ->
      do_split_at_top_level_comma(
        rest,
        paren_depth,
        brace_depth,
        current <> char,
        acc,
      )
  }
}
