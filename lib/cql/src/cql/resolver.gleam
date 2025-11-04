import cql/parser.{type Exp, type ExpContainer, Div, ExpContainer, OperatorExpr}

pub type Primitives {
  // good over total requires a top level division operator
  GoodOverTotal(numerator: Exp, denominator: Exp)
}

pub fn resolve_primitives(
  exp_container: ExpContainer,
) -> Result(Primitives, String) {
  case exp_container {
    ExpContainer(exp) ->
      case exp {
        OperatorExpr(left, right, Div) -> Ok(GoodOverTotal(left, right))
        _ -> Error("Invalid expression")
      }
  }
}
