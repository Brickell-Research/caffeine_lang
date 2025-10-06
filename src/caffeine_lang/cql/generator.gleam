import caffeine_lang/cql/parser.{
  type Exp, type Operator, type Primary, Add, Div, Mul, PrimaryExp, PrimaryWord,
  Sub,
}
import caffeine_lang/cql/resolver.{type Primitives, GoodOverTotal}
import gleam/option.{type Option, None, Some}

// Datadog
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

fn exp_to_string(exp: Exp) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_string(primary, None)
    parser.OperatorExpr(numerator:, denominator:, operator:) ->
      exp_to_string_with_context(numerator, Some(operator), True)
      <> " "
      <> operator_to_datadog_query(operator)
      <> " "
      <> exp_to_string_with_context(denominator, Some(operator), False)
  }
}

fn exp_to_string_with_context(
  exp: Exp,
  parent_op: Option(Operator),
  _is_left: Bool,
) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_string(primary, parent_op)
    parser.OperatorExpr(numerator:, denominator:, operator:) ->
      exp_to_string_with_context(numerator, Some(operator), True)
      <> " "
      <> operator_to_datadog_query(operator)
      <> " "
      <> exp_to_string_with_context(denominator, Some(operator), False)
  }
}

fn primary_to_string(primary: Primary, parent_op: Option(Operator)) -> String {
  case primary {
    PrimaryWord(word:) -> word.value
    PrimaryExp(exp:) -> {
      // Check if parentheses are needed
      let needs_parens = case exp, parent_op {
        // If there's no parent operator, we don't need parens
        _, None -> False
        // If the inner expression is just a primary, check if it needs parens
        parser.Primary(_), _ -> False
        // If inner is an operator expression, check precedence
        parser.OperatorExpr(operator: inner_op, ..), Some(parent) ->
          needs_parentheses(inner_op, parent)
      }
      case needs_parens {
        True -> "(" <> exp_to_string(exp) <> ")"
        False -> exp_to_string(exp)
      }
    }
  }
}

fn needs_parentheses(inner_op: Operator, parent_op: Operator) -> Bool {
  let inner_prec = operator_precedence(inner_op)
  let parent_prec = operator_precedence(parent_op)
  inner_prec < parent_prec
}

fn operator_precedence(op: Operator) -> Int {
  case op {
    Add | Sub -> 1
    Mul | Div -> 2
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
