import caffeine_lang/cql/parser.{
  type Exp, type Operator, type Primary, PrimaryExp, PrimaryWord,
}
import caffeine_lang/cql/resolver.{type Primitives, GoodOverTotal}

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

pub fn numerator_exp_to_datadog_query(exp: Exp) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_datadog_query(primary)
    parser.OperatorExpr(numerator:, denominator:, operator:) ->
      operator_expr_to_datadog_query(numerator, denominator, operator)
  }
}

pub fn denominator_exp_to_datadog_query(exp: Exp) -> String {
  numerator_exp_to_datadog_query(exp)
}

pub fn primary_to_datadog_query(primary: Primary) -> String {
  case primary {
    PrimaryWord(word:) -> word.value
    PrimaryExp(exp:) -> numerator_exp_to_datadog_query(exp)
  }
}

pub fn operator_expr_to_datadog_query(
  numerator: Exp,
  denominator: Exp,
  operator: Operator,
) -> String {
  numerator_exp_to_datadog_query(numerator)
  <> " "
  <> operator_to_datadog_query(operator)
  <> " "
  <> denominator_exp_to_datadog_query(denominator)
}

pub fn operator_to_datadog_query(operator: parser.Operator) -> String {
  case operator {
    parser.Add -> "+"
    parser.Sub -> "-"
    parser.Mul -> "*"
    parser.Div -> "/"
  }
}
