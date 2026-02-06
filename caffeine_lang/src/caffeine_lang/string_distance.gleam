/// String distance utilities for "did you mean?" suggestions.
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Computes the Levenshtein edit distance between two strings.
pub fn levenshtein(a: String, b: String) -> Int {
  let a_graphemes = string.to_graphemes(a)
  let b_graphemes = string.to_graphemes(b)
  let b_len = list.length(b_graphemes)

  // Initial row: [0, 1, 2, ..., b_len]
  let initial_row = list.range(0, b_len)

  let result_row =
    list.index_fold(a_graphemes, initial_row, fn(prev_row, a_char, i) {
      build_row(prev_row, b_graphemes, a_char, i + 1)
    })

  // Last element of the final row is the distance.
  case list.last(result_row) {
    Ok(d) -> d
    // Cannot happen: row always has at least one element.
    Error(Nil) -> 0
  }
}

/// Builds one row of the Levenshtein matrix.
fn build_row(
  prev_row: List(Int),
  b_graphemes: List(String),
  a_char: String,
  initial_val: Int,
) -> List(Int) {
  let #(row, _) =
    build_row_loop(prev_row, b_graphemes, a_char, [initial_val], initial_val)
  list.reverse(row)
}

fn build_row_loop(
  prev_row: List(Int),
  b_remaining: List(String),
  a_char: String,
  acc: List(Int),
  prev_val: Int,
) -> #(List(Int), Int) {
  case b_remaining, prev_row {
    [], _ -> #(acc, prev_val)
    [b_char, ..b_rest], [diag, ..prev_rest] -> {
      let above = case prev_rest {
        [v, ..] -> v
        [] -> 0
      }
      let cost = case a_char == b_char {
        True -> 0
        False -> 1
      }
      let val = int.min(prev_val + 1, int.min(above + 1, diag + cost))
      build_row_loop(prev_rest, b_rest, a_char, [val, ..acc], val)
    }
    _, [] -> #(acc, prev_val)
  }
}

/// Returns the closest match from a list of candidates, if within threshold.
/// Threshold: distance <= max(2, ceil(length(target) * 0.4)).
pub fn closest_match(target: String, candidates: List(String)) -> Option(String) {
  let target_len = string.length(target)
  let threshold =
    int.max(2, float.truncate(int.to_float(target_len) *. 0.4 +. 0.99))

  let result =
    list.fold(candidates, option.None, fn(best, candidate) {
      let dist = levenshtein(target, candidate)
      case dist > threshold {
        True -> best
        False ->
          case best {
            option.None -> option.Some(#(candidate, dist))
            option.Some(#(_, best_dist)) ->
              case dist < best_dist {
                True -> option.Some(#(candidate, dist))
                False -> best
              }
          }
      }
    })

  case result {
    option.Some(#(name, _)) -> option.Some(name)
    option.None -> option.None
  }
}
