import caffeine_lang/cql/parser.{
  type Exp, type ExpContainer, Div, ExpContainer, OperatorExpr,
}

// For GoodOverTotal, the only valid top level operator is division.
pub type Primitives {
  GoodOverTotal(numerator: Exp, denominator: Exp)
}

pub fn resolve_primitives(
  exp_container: ExpContainer,
) -> Result(Primitives, String) {
  case exp_container {
    ExpContainer(OperatorExpr(left, right, Div)) -> {
      Ok(GoodOverTotal(left, right))
    }
    _ -> Error("Invalid expression")
  }
}
