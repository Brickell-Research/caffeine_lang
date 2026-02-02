import caffeine_query_language/ast.{
  type Comparator, type Exp, type Operator, type Primary,
}
import gleam/float
import gleam/int
import gleam/option.{type Option}
import gleam/string

/// Converts an expression AST node to its string representation.
@internal
pub fn exp_to_string(exp: Exp) -> String {
  case exp {
    ast.Primary(primary:) -> primary_to_string(primary, option.None)
    ast.TimeSliceExpr(spec) ->
      "time_slice("
      <> spec.query
      <> " "
      <> comparator_to_string(spec.comparator)
      <> " "
      <> float_to_string(spec.threshold)
      <> " per "
      <> float_to_string(spec.interval_seconds)
      <> "s)"
    ast.OperatorExpr(numerator:, denominator:, operator:) -> {
      case operator, is_path_expression(exp) {
        ast.Div, True -> {
          exp_to_string_no_spaces(exp)
        }
        _, _ -> {
          let left =
            exp_to_string_with_context(numerator, option.Some(operator), True)
          let right =
            exp_to_string_with_context(
              denominator,
              option.Some(operator),
              False,
            )
          let op = operator_to_string(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

/// Converts a CQL comparator to its string representation.
fn comparator_to_string(comparator: Comparator) -> String {
  case comparator {
    ast.LessThan -> "<"
    ast.LessThanOrEqualTo -> "<="
    ast.GreaterThan -> ">"
    ast.GreaterThanOrEqualTo -> ">="
  }
}

/// Converts a CQL operator to its string representation.
@internal
pub fn operator_to_string(operator: Operator) -> String {
  case operator {
    ast.Add -> "+"
    ast.Sub -> "-"
    ast.Mul -> "*"
    ast.Div -> "/"
  }
}

fn float_to_string(f: Float) -> String {
  let truncated = float.truncate(f)
  let is_whole = int.to_float(truncated) == f
  case is_whole {
    True -> int.to_string(truncated)
    False -> float.to_string(f)
  }
}

fn is_path_expression(exp: Exp) -> Bool {
  case get_leftmost_word(exp) {
    option.Some(w) -> {
      case string.ends_with(w, ":") {
        True -> all_divisions(exp)
        False -> False
      }
    }
    option.None -> False
  }
}

fn get_leftmost_word(exp: Exp) -> Option(String) {
  case exp {
    ast.Primary(ast.PrimaryWord(ast.Word(w))) -> option.Some(w)
    ast.Primary(ast.PrimaryExp(inner_exp)) -> get_leftmost_word(inner_exp)
    ast.TimeSliceExpr(_) -> option.None
    ast.OperatorExpr(left, _, _) -> get_leftmost_word(left)
  }
}

fn all_divisions(exp: Exp) -> Bool {
  case exp {
    ast.Primary(_) -> True
    ast.OperatorExpr(left, right, ast.Div) ->
      all_divisions(left) && all_divisions(right)
    _ -> False
  }
}

fn exp_to_string_no_spaces(exp: Exp) -> String {
  case exp {
    ast.Primary(ast.PrimaryWord(ast.Word(w))) -> w
    ast.OperatorExpr(left, right, ast.Div) ->
      exp_to_string_no_spaces(left) <> "/" <> exp_to_string_no_spaces(right)
    _ -> exp_to_string(exp)
  }
}

fn exp_to_string_with_context(
  exp: Exp,
  parent_op: Option(Operator),
  _is_left: Bool,
) -> String {
  case exp {
    ast.Primary(primary:) -> primary_to_string(primary, parent_op)
    ast.TimeSliceExpr(_) -> exp_to_string(exp)
    ast.OperatorExpr(numerator:, denominator:, operator:) -> {
      case operator, is_path_expression(exp) {
        ast.Div, True -> exp_to_string_no_spaces(exp)
        _, _ -> {
          let left =
            exp_to_string_with_context(numerator, option.Some(operator), True)
          let right =
            exp_to_string_with_context(
              denominator,
              option.Some(operator),
              False,
            )
          let op = operator_to_string(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

fn primary_to_string(primary: Primary, _parent_op: Option(Operator)) -> String {
  case primary {
    ast.PrimaryWord(word:) -> word.value
    ast.PrimaryExp(exp:) -> {
      "(" <> exp_to_string(exp) <> ")"
    }
  }
}

/// Strips outer parentheses from a string if they wrap the entire expression.
/// E.g., "(a + b)" -> "a + b", but "(a + b) * c" stays unchanged.
@internal
pub fn strip_outer_parens(s: String) -> String {
  let trimmed = string.trim(s)
  case string.starts_with(trimmed, "(") && string.ends_with(trimmed, ")") {
    True -> {
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      case is_balanced(inner, 0) {
        True -> inner
        False -> trimmed
      }
    }
    False -> trimmed
  }
}

fn is_balanced(s: String, depth: Int) -> Bool {
  case string.pop_grapheme(s) {
    Error(_) -> depth == 0
    Ok(#("(", rest)) -> is_balanced(rest, depth + 1)
    Ok(#(")", rest)) ->
      case depth {
        0 -> False
        _ -> is_balanced(rest, depth - 1)
      }
    Ok(#(_, rest)) -> is_balanced(rest, depth)
  }
}
