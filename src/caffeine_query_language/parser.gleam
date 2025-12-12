import caffeine_query_language/errors
import gleam/float
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ===== Types =====

/// A complete query containing a single expression.
pub type Query {
  Query(exp: Exp)
}

/// Container for a parsed expression, used as the top-level parse result.
pub type ExpContainer {
  ExpContainer(exp: Exp)
}

/// Arithmetic operators supported in CQL expressions.
pub type Operator {
  Add
  Sub
  Mul
  Div
}

/// Comparators for time slice expressions.
pub type Comparator {
  LessThan
  LessThanOrEqualTo
  GreaterThan
  GreaterThanOrEqualTo
}

/// Time slice specification containing query, comparator, threshold, and interval.
pub type TimeSliceExp {
  TimeSliceExp(
    query: String,
    comparator: Comparator,
    threshold: Float,
    interval_seconds: Float,
  )
}

/// An expression in the CQL AST, either an operator expression or a primary.
pub type Exp {
  TimeSliceExpr(spec: TimeSliceExp)
  OperatorExpr(numerator: Exp, denominator: Exp, operator: Operator)
  Primary(primary: Primary)
}

/// A primary expression, either a word (identifier) or a parenthesized expression.
pub type Primary {
  PrimaryWord(word: Word)
  PrimaryExp(exp: Exp)
}

/// A word (identifier) in the expression.
pub type Word {
  Word(value: String)
}

//==========================================

/// Parses a CQL expression string into an ExpContainer.
/// Returns an error if the input cannot be parsed.
pub fn parse_expr(input: String) -> Result(ExpContainer, String) {
  use exp <- result.try(do_parse_expr(input))
  Ok(ExpContainer(exp))
}

/// Parses a CQL expression string into an Exp AST node.
/// Handles parenthesized expressions and operator precedence.
fn do_parse_expr(input: String) -> Result(Exp, String) {
  let trimmed = string.trim(input)

  case is_fully_parenthesized(trimmed) {
    True -> {
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      use inner_exp <- result.try(do_parse_expr(inner))
      Ok(Primary(PrimaryExp(inner_exp)))
    }
    False -> {
      let operators = [#("+", Add), #("-", Sub), #("*", Mul), #("/", Div)]
      try_operators(trimmed, operators)
    }
  }
}

fn is_fully_parenthesized(input: String) -> Bool {
  string.starts_with(input, "(")
  && string.ends_with(input, ")")
  && { string.length(input) >= 2 && is_balanced_parens(input, 1, 1) }
}

fn try_operators(
  input: String,
  operators: List(#(String, Operator)),
) -> Result(Exp, String) {
  case operators {
    [] -> {
      // No operators found, check if this is a keyword expression
      case try_parse_keyword_expr(input) {
        Ok(exp) -> Ok(exp)
        Error(err) -> {
          // If it looks like a time_slice but has invalid syntax, propagate error
          case
            string.starts_with(input, "time_slice(")
            && string.ends_with(input, ")")
          {
            True -> Error(err)
            False -> {
              let word = Word(input)
              Ok(Primary(PrimaryWord(word)))
            }
          }
        }
      }
    }
    [#(op_str, op), ..rest] -> {
      case find_operator(input, op_str) {
        Ok(#(left, right)) -> {
          use left_exp <- result.try(do_parse_expr(left))
          use right_exp <- result.try(do_parse_expr(right))
          Ok(OperatorExpr(left_exp, right_exp, op))
        }
        Error(_) -> try_operators(input, rest)
      }
    }
  }
}

/// Attempts to parse a keyword expression like "time_slice(...)".
/// Returns Error if the input is not a keyword expression.
fn try_parse_keyword_expr(input: String) -> Result(Exp, String) {
  // Check for time_slice keyword
  case string.starts_with(input, "time_slice(") && string.ends_with(input, ")")
  {
    True -> {
      // Extract the inner content (everything between "time_slice(" and ")")
      let prefix_len = string.length("time_slice(")
      let inner_len = string.length(input) - prefix_len - 1
      let inner = string.slice(input, prefix_len, inner_len)
      use spec <- result.try(parse_time_slice_spec(inner))
      Ok(TimeSliceExpr(spec))
    }
    False -> Error("Not a keyword expression")
  }
}

/// Parses the inner content of a time_slice expression.
/// Format: "<query> <comparator> <threshold> per <interval>"
/// Example: "avg:system.cpu > 80 per 300s"
fn parse_time_slice_spec(input: String) -> Result(TimeSliceExp, String) {
  let trimmed = string.trim(input)

  // Check for empty input
  case trimmed {
    "" -> Error("Empty time_slice expression")
    _ -> {
      // Find the comparator and split on it
      use #(query, comparator, rest) <- result.try(find_comparator(trimmed))

      // Validate query is not empty
      let query_trimmed = string.trim(query)
      case query_trimmed {
        "" -> Error("Missing query in time_slice expression")
        _ -> {
          // Find "per" keyword and split threshold from interval
          use #(threshold_str, interval_str) <- result.try(split_on_per(rest))

          // Parse threshold as float
          use threshold <- result.try(parse_threshold(threshold_str))

          // Parse interval (e.g., "10s", "5m", "1h", "1.5h")
          use interval_seconds <- result.try(parse_interval(interval_str))

          Ok(TimeSliceExp(
            query: query_trimmed,
            comparator: comparator,
            threshold: threshold,
            interval_seconds: interval_seconds,
          ))
        }
      }
    }
  }
}

/// Finds a comparator in the input and splits into (query, comparator, rest).
fn find_comparator(
  input: String,
) -> Result(#(String, Comparator, String), String) {
  // Try comparators in order (longer ones first to avoid partial matches)
  let comparators = [
    #(">=", GreaterThanOrEqualTo),
    #("<=", LessThanOrEqualTo),
    #(">", GreaterThan),
    #("<", LessThan),
  ]

  find_comparator_loop(input, comparators)
}

fn find_comparator_loop(
  input: String,
  comparators: List(#(String, Comparator)),
) -> Result(#(String, Comparator, String), String) {
  case comparators {
    [] -> Error("No comparator found in time_slice expression")
    [#(comp_str, comp), ..rest] -> {
      case find_substring_position(input, comp_str) {
        Some(pos) -> {
          let query = string.slice(input, 0, pos)
          let rest_start = pos + string.length(comp_str)
          let rest_len = string.length(input) - rest_start
          let rest_str = string.slice(input, rest_start, rest_len)
          Ok(#(query, comp, rest_str))
        }
        None -> find_comparator_loop(input, rest)
      }
    }
  }
}

/// Finds the position of a substring in a string.
fn find_substring_position(haystack: String, needle: String) -> Option(Int) {
  find_substring_position_loop(haystack, needle, 0)
}

fn find_substring_position_loop(
  haystack: String,
  needle: String,
  pos: Int,
) -> Option(Int) {
  let needle_len = string.length(needle)
  let haystack_len = string.length(haystack)

  case pos + needle_len > haystack_len {
    True -> None
    False -> {
      case string.slice(haystack, pos, needle_len) == needle {
        True -> Some(pos)
        False -> find_substring_position_loop(haystack, needle, pos + 1)
      }
    }
  }
}

/// Splits on "per" keyword, returning (threshold_str, interval_str).
fn split_on_per(input: String) -> Result(#(String, String), String) {
  case find_substring_position(input, "per") {
    Some(pos) -> {
      let threshold_str = string.trim(string.slice(input, 0, pos))
      let rest_start = pos + 3
      // "per" is 3 chars
      let rest_len = string.length(input) - rest_start
      let interval_str = string.trim(string.slice(input, rest_start, rest_len))
      Ok(#(threshold_str, interval_str))
    }
    None -> Error("Missing 'per' keyword in time_slice expression")
  }
}

/// Parses a threshold value as a float.
fn parse_threshold(input: String) -> Result(Float, String) {
  let trimmed = string.trim(input)
  case trimmed {
    "" -> Error("Missing threshold in time_slice expression")
    _ ->
      case float.parse(trimmed) {
        Ok(f) -> Ok(f)
        Error(_) ->
          case parse_int_as_float(trimmed) {
            Ok(f) -> Ok(f)
            Error(_) ->
              Error(
                "Invalid threshold '" <> trimmed <> "' in time_slice expression",
              )
          }
      }
  }
}

/// Parses an integer string as a float.
fn parse_int_as_float(input: String) -> Result(Float, String) {
  case string.contains(input, ".") {
    True -> Error("Not an integer")
    False ->
      float.parse(input <> ".0")
      |> result.map_error(fn(_) { "Invalid number" })
  }
}

/// Parses an interval like "10s", "5m", "1h", "1.5h" into seconds.
fn parse_interval(input: String) -> Result(Float, String) {
  let trimmed = string.trim(input)
  case trimmed {
    "" -> Error("Missing interval in time_slice expression")
    _ -> {
      // Get the unit (last character)
      let len = string.length(trimmed)
      let unit = string.slice(trimmed, len - 1, 1)
      let number_part = string.slice(trimmed, 0, len - 1)

      use multiplier <- result.try(case unit {
        "s" -> Ok(1.0)
        "m" -> Ok(60.0)
        "h" -> Ok(3600.0)
        _ ->
          Error("Invalid interval unit '" <> unit <> "' (expected s, m, or h)")
      })

      use number <- result.try(case float.parse(number_part) {
        Ok(f) -> Ok(f)
        Error(_) ->
          case parse_int_as_float(number_part) {
            Ok(f) -> Ok(f)
            Error(_) ->
              Error("Invalid interval number '" <> number_part <> "'")
          }
      })

      Ok(number *. multiplier)
    }
  }
}

fn find_operator(
  input: String,
  operator: String,
) -> Result(#(String, String), errors.CQLError) {
  find_rightmost_operator_at_level(input, operator, 0, 0, -1)
}

/// Checks if parentheses are balanced in the input string starting from a position.
/// Used to validate parenthesized expressions during parsing.
@internal
pub fn is_balanced_parens(input: String, pos: Int, count: Int) -> Bool {
  case pos >= string.length(input) {
    True -> count == 0
    False -> {
      let new_count = count_parens(count, input, pos)
      let does_not_close_too_early =
        !{ { new_count == 0 } && !is_last_char(input, pos) }

      does_not_close_too_early && is_balanced_parens(input, pos + 1, new_count)
    }
  }
}

/// Returns true if the position is at the last character of the input string.
@internal
pub fn is_last_char(input: String, pos: Int) -> Bool {
  let is_empty = string.is_empty(input)
  let is_last = pos == string.length(input) - 1

  is_empty || is_last
}

/// Finds the rightmost occurrence of an operator at parenthesis level 0.
/// Returns the left and right parts of the expression split at the operator.
@internal
pub fn find_rightmost_operator_at_level(
  input: String,
  operator: String,
  start_pos: Int,
  paren_level: Int,
  rightmost_pos: Int,
) -> Result(#(String, String), errors.CQLError) {
  let operator_length = string.length(operator)

  case start_pos >= string.length(input) {
    True ->
      case rightmost_pos {
        -1 -> Error(errors.CQLParserError("Operator not found"))
        pos -> {
          // Split at the rightmost operator position
          let left = string.trim(string.slice(input, 0, pos))
          let right_start = pos + operator_length
          let right_length = string.length(input) - right_start
          let right =
            string.trim(string.slice(input, right_start, right_length))
          Ok(#(left, right))
        }
      }
    False -> {
      let new_paren_level = count_parens(paren_level, input, start_pos)
      let new_rightmost_pos = case
        new_paren_level == 0
        && string.slice(input, start_pos, operator_length) == operator
      {
        True -> start_pos
        False -> rightmost_pos
      }

      find_rightmost_operator_at_level(
        input,
        operator,
        start_pos + 1,
        new_paren_level,
        new_rightmost_pos,
      )
    }
  }
}

fn count_parens(cur_count: Int, input: String, pos: Int) -> Int {
  let char = string.slice(input, pos, 1)
  case char {
    "(" -> cur_count + 1
    ")" -> cur_count - 1
    _ -> cur_count
  }
}
