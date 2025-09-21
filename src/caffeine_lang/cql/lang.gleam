import caffeine_lang/cql/types.{
  type Exp, type ExpContainer, type Operator, Add, Div, ExpContainer, Mul,
  OperatorExpr, Primary, PrimaryExp, PrimaryWord, Sub, Word,
}
import gleam/result
import gleam/string

pub fn parse_expr(input: String) -> Result(ExpContainer, String) {
  use exp <- result.try(do_parse_expr(input))
  Ok(ExpContainer(exp))
}

pub fn do_parse_expr(input: String) -> Result(Exp, String) {
  let trimmed = string.trim(input)

  // Handle parenthesized expressions
  case string.starts_with(trimmed, "(") && string.ends_with(trimmed, ")") {
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
  find_operator_at_level(input, operator, 0, 0)
}

fn find_operator_at_level(
  input: String,
  operator: String,
  start_pos: Int,
  paren_level: Int,
) -> Result(#(String, String), String) {
  case start_pos >= string.length(input) {
    True -> Error("Operator not found")
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

      case is_target_operator {
        True -> {
          let left = string.trim(string.slice(input, 0, start_pos))
          let right_start = start_pos + string.length(operator)
          let right_length = string.length(input) - right_start
          let right =
            string.trim(string.slice(input, right_start, right_length))
          Ok(#(left, right))
        }
        False -> {
          find_operator_at_level(
            input,
            operator,
            start_pos + 1,
            new_paren_level,
          )
        }
      }
    }
  }
}
