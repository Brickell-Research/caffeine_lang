import gleam/result
import gleam/string

pub type Query {
  Query(exp: Exp)
}

pub type ExpContainer {
  ExpContainer(exp: Exp)
}

pub type Operator {
  Add
  Sub
  Mul
  Div
}

pub type Exp {
  OperatorExpr(numerator: Exp, denominator: Exp, operator: Operator)
  Primary(primary: Primary)
}

pub type Primary {
  PrimaryWord(word: Word)
  PrimaryExp(exp: Exp)
}

pub type Word {
  Word(value: String)
}

/// parse_expr
pub fn parse_expr(input: String) -> Result(ExpContainer, String) {
  use exp <- result.try(do_parse_expr(input))
  Ok(ExpContainer(exp))
}

pub fn do_parse_expr(input: String) -> Result(Exp, String) {
  let trimmed = string.trim(input)

  case is_fully_parenthesized(trimmed) {
    True -> {
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      use inner_exp <- result.try(do_parse_expr(inner))
      Ok(Primary(PrimaryExp(inner_exp)))
    }
    False -> {
      // Try operators in precedence order (lowest to highest)
      let operators = [#("+", Add), #("-", Sub), #("*", Mul), #("/", Div)]
      try_operators(trimmed, operators)
    }
  }
}

fn is_fully_parenthesized(input: String) -> Bool {
  string.starts_with(input, "(")
  && string.ends_with(input, ")")
  && { string.length(input) >= 2 && check_balanced_parens(input, 1, 1) }
}

fn try_operators(
  input: String,
  operators: List(#(String, Operator)),
) -> Result(Exp, String) {
  case operators {
    [] -> {
      let word = Word(input)
      Ok(Primary(PrimaryWord(word)))
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

fn find_operator(
  input: String,
  operator: String,
) -> Result(#(String, String), String) {
  find_rightmost_operator_at_level(input, operator, 0, 0, -1)
}

fn check_balanced_parens(input: String, pos: Int, count: Int) -> Bool {
  case pos >= string.length(input) {
    True -> count == 0
    // Should end with count 0 (all parens closed)
    False -> {
      let char = string.slice(input, pos, 1)
      let new_count = case char {
        "(" -> count + 1
        ")" -> count - 1
        _ -> count
      }
      case new_count == 0 && pos < string.length(input) - 1 {
        True -> False
        // Parentheses closed before the end
        False -> check_balanced_parens(input, pos + 1, new_count)
      }
    }
  }
}

fn find_rightmost_operator_at_level(
  input: String,
  operator: String,
  start_pos: Int,
  paren_level: Int,
  rightmost_pos: Int,
) -> Result(#(String, String), String) {
  case start_pos >= string.length(input) {
    True ->
      case rightmost_pos {
        -1 -> Error("Operator not found")
        pos -> {
          let left = string.trim(string.slice(input, 0, pos))
          let right_start = pos + string.length(operator)
          let right_length = string.length(input) - right_start
          let right =
            string.trim(string.slice(input, right_start, right_length))
          Ok(#(left, right))
        }
      }
    False -> {
      let char = string.slice(input, start_pos, 1)
      let new_paren_level = case char {
        "(" -> paren_level + 1
        ")" -> paren_level - 1
        _ -> paren_level
      }

      let is_target_operator =
        paren_level == 0
        && string.slice(input, start_pos, string.length(operator)) == operator

      let new_rightmost_pos = case is_target_operator {
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
