import caffeine_query_language/errors
import caffeine_query_language/parser.{
  type Exp, type ExpContainer, Div, ExpContainer, OperatorExpr,
}

/// Supported primitive query types that can be resolved from CQL expressions.
/// Each primitive represents a specific SLO calculation pattern.
pub type Primitives {
  /// Good over total requires a top level division operator.
  /// Represents an SLO where the numerator is the "good" events
  /// and the denominator is the "total" events.
  GoodOverTotal(numerator: Exp, denominator: Exp)
}

/// Resolves a parsed CQL expression into a primitive type.
/// Currently only supports GoodOverTotal (division at the top level).
/// Returns an error if the expression doesn't match a known primitive pattern.
pub fn resolve_primitives(
  exp_container: ExpContainer,
) -> Result(Primitives, errors.CQLError) {
  case exp_container {
    ExpContainer(exp) ->
      case exp {
        OperatorExpr(left, right, Div) -> Ok(GoodOverTotal(left, right))
        _ ->
          Error(errors.CQLResolverError(
            "Invalid expression. Expected a top level division operator.",
          ))
      }
  }
}
