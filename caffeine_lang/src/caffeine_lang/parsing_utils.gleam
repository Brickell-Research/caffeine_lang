import gleam/list
import gleam/result
import gleam/string

/// Splits a string at commas that are not inside parentheses or curly braces.
/// Used by collection and modifier type parsers for nested type arguments.
@internal
pub fn split_at_top_level_comma(s: String) -> List(String) {
  let chars = string.to_graphemes(s)
  do_split_at_top_level_comma(chars, 0, 0, "", [])
}

/// Extracts the content inside the outermost pair of parentheses,
/// properly handling nested parentheses.
/// Returns Error if there's content after the closing paren (e.g., refinement constraints).
@internal
pub fn extract_paren_content(raw: String) -> Result(String, Nil) {
  case string.split_once(raw, "(") {
    Error(_) -> Error(Nil)
    Ok(#(_, after_open)) -> {
      // Find the matching close paren by tracking nesting depth
      use #(content, rest) <- result.try(find_matching_close_paren(
        after_open,
        1,
        "",
      ))
      // If there's non-whitespace content after the closing paren,
      // this is likely a refinement type and we should fail
      case string.trim(rest) {
        "" -> Ok(string.trim(content))
        _ -> Error(Nil)
      }
    }
  }
}

/// Finds the matching closing parenthesis, tracking nesting depth.
/// Returns the content before the matching close and the rest after it.
fn find_matching_close_paren(
  s: String,
  depth: Int,
  acc: String,
) -> Result(#(String, String), Nil) {
  case string.pop_grapheme(s) {
    Error(_) -> Error(Nil)
    Ok(#("(", rest)) -> find_matching_close_paren(rest, depth + 1, acc <> "(")
    Ok(#(")", rest)) -> {
      case depth {
        1 -> Ok(#(acc, rest))
        _ -> find_matching_close_paren(rest, depth - 1, acc <> ")")
      }
    }
    Ok(#(char, rest)) -> find_matching_close_paren(rest, depth, acc <> char)
  }
}

/// Extracts the trimmed content inside the outermost parentheses.
/// Falls back to trimming the raw string if no valid parenthesized content is found.
@internal
pub fn paren_innerds_trimmed(raw: String) -> String {
  case extract_paren_content(raw) {
    Ok(content) -> content
    Error(_) -> string.trim(raw)
  }
}

/// Splits a parenthesized type string at the top-level comma only.
/// Handles nested parentheses correctly.
/// Example: "(String, Dict(String, Integer))" -> ["String", "Dict(String, Integer)"]
@internal
pub fn paren_innerds_split_and_trimmed(raw: String) -> List(String) {
  case extract_paren_content(raw) {
    Ok(content) -> split_at_top_level_comma(content)
    Error(_) -> []
  }
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
