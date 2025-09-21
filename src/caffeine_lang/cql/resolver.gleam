import caffeine_lang/cql/parser.{
  type Exp, type ExpContainer, Add, Div, ExpContainer, OperatorExpr,
}

// For GoodOverTotal, the only valid top level operator is division.
pub type Primitives {
  GoodOverTotal(numerator: Exp, denominator: Exp)
}

pub fn resolve_primitives(
  exp_container: ExpContainer,
) -> Result(Primitives, String) {
  case exp_container {
    ExpContainer(exp) -> find_division_in_exp(exp)
  }
}

fn find_division_in_exp(exp: Exp) -> Result(Primitives, String) {
  case exp {
    OperatorExpr(left, OperatorExpr(num, denom, Div), _) -> {
      // Pattern: left_expr + (num / denom) or similar
      // Treat as (left_expr + num) / denom
      Ok(GoodOverTotal(OperatorExpr(left, num, Add), denom))
    }
    OperatorExpr(left, right, Div) -> {
      Ok(GoodOverTotal(left, right))
    }
    _ -> Error("Invalid expression")
  }
}
