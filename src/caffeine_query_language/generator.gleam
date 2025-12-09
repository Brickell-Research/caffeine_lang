import caffeine_query_language/parser.{
  type Exp, type Operator, type Primary, PrimaryExp, PrimaryWord,
}
import caffeine_query_language/resolver.{type Primitives, GoodOverTotal}
import gleam/option.{type Option, None, Some}
import gleam/string

/// Generates a Datadog query block from a resolved primitive.
/// Formats the numerator and denominator as a Datadog SLO query structure.
pub fn generate_datadog_query(primitive: Primitives) -> String {
  case primitive {
    GoodOverTotal(numerator, denominator) -> {
      "query {\n"
      <> "    numerator = \""
      <> numerator_exp_to_datadog_query(numerator)
      <> "\"\n"
      <> "    denominator = \""
      <> denominator_exp_to_datadog_query(denominator)
      <> "\"\n"
      <> "  }\n"
    }
  }
}

fn numerator_exp_to_datadog_query(exp: Exp) -> String {
  // Unwrap outer PrimaryExp at top level only
  case exp {
    parser.Primary(PrimaryExp(exp:)) -> exp_to_string(exp)
    _ -> exp_to_string(exp)
  }
}

fn denominator_exp_to_datadog_query(exp: Exp) -> String {
  // Unwrap outer PrimaryExp at top level only
  case exp {
    parser.Primary(PrimaryExp(exp:)) -> exp_to_string(exp)
    _ -> exp_to_string(exp)
  }
}

pub fn exp_to_string(exp: Exp) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_string(primary, None)
    parser.OperatorExpr(numerator:, denominator:, operator:) -> {
      // Check if this entire expression tree is a path (all divisions with path-like components)
      case operator, is_path_expression(exp) {
        parser.Div, True -> {
          // This is a path, render without spaces
          exp_to_string_no_spaces(exp)
        }
        _, _ -> {
          // Normal expression with spaces
          let left = exp_to_string_with_context(numerator, Some(operator), True)
          let right =
            exp_to_string_with_context(denominator, Some(operator), False)
          let op = operator_to_datadog_query(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

// Check if an expression is a path (all divisions with simple word components)
// A path expression starts with a field name ending in colon (like http.url_details.path:)
fn is_path_expression(exp: Exp) -> Bool {
  // First check if the leftmost component is a field name (ends with :)
  case get_leftmost_word(exp) {
    Some(w) -> {
      case string.ends_with(w, ":") {
        True -> all_divisions(exp)
        False -> False
      }
    }
    None -> False
  }
}

// Get the leftmost word in an expression tree
fn get_leftmost_word(exp: Exp) -> Option(String) {
  case exp {
    parser.Primary(parser.PrimaryWord(parser.Word(w))) -> Some(w)
    parser.Primary(parser.PrimaryExp(inner_exp)) -> get_leftmost_word(inner_exp)
    parser.OperatorExpr(left, _, _) -> get_leftmost_word(left)
  }
}

// Check if an expression is all divisions (no other operators)
fn all_divisions(exp: Exp) -> Bool {
  case exp {
    parser.Primary(_) -> True
    parser.OperatorExpr(left, right, parser.Div) ->
      all_divisions(left) && all_divisions(right)
    _ -> False
  }
}

// Convert expression to string without spaces (for paths)
fn exp_to_string_no_spaces(exp: Exp) -> String {
  case exp {
    parser.Primary(parser.PrimaryWord(parser.Word(w))) -> w
    parser.OperatorExpr(left, right, parser.Div) ->
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
    parser.Primary(primary:) -> primary_to_string(primary, parent_op)
    parser.OperatorExpr(numerator:, denominator:, operator:) -> {
      // Check if this is a path expression to avoid adding spaces
      // This is important when the division is part of a larger expression (e.g., with AND)
      case operator, is_path_expression(exp) {
        parser.Div, True -> exp_to_string_no_spaces(exp)
        _, _ -> {
          // Not a path, render with spaces
          let left = exp_to_string_with_context(numerator, Some(operator), True)
          let right =
            exp_to_string_with_context(denominator, Some(operator), False)
          let op = operator_to_datadog_query(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

fn primary_to_string(primary: Primary, _parent_op: Option(Operator)) -> String {
  case primary {
    PrimaryWord(word:) -> word.value
    PrimaryExp(exp:) -> {
      // Always preserve explicit parentheses from the original input
      "(" <> exp_to_string(exp) <> ")"
    }
  }
}

pub fn operator_to_datadog_query(operator: parser.Operator) -> String {
  case operator {
    parser.Add -> "+"
    parser.Sub -> "-"
    parser.Mul -> "*"
    parser.Div -> "/"
  }
}
