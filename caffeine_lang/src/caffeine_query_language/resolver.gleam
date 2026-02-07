import caffeine_lang/errors.{type CompilationError}
import caffeine_query_language/ast.{type Comparator, type Exp}
import gleam/bool
import gleam/float

/// Supported primitive query types that can be resolved from CQL expressions.
/// Each primitive represents a specific SLO calculation pattern.
pub type Primitives {
  /// Good over total requires a top level division operator.
  /// Represents an SLO where the numerator is the "good" events
  /// and the denominator is the "total" events.
  GoodOverTotal(numerator: Exp, denominator: Exp)
  TimeSlice(
    comparator: Comparator,
    interval_in_seconds: Int,
    threshold: Float,
    query: String,
  )
}

/// Converts a comparator to its quoted string representation.
@internal
pub fn comparator_to_string(comparator: Comparator) {
  case comparator {
    ast.LessThan -> "\"<\""
    ast.LessThanOrEqualTo -> "\"<=\""
    ast.GreaterThan -> "\">\""
    ast.GreaterThanOrEqualTo -> "\">=\""
  }
}

/// Resolves a parsed CQL expression into a primitive type.
/// Supports GoodOverTotal (division at the top level) and TimeSlice.
/// Returns an error if the expression doesn't match a known primitive pattern.
@internal
pub fn resolve_primitives(exp: Exp) -> Result(Primitives, CompilationError) {
  case exp {
    ast.OperatorExpr(left, right, ast.Div) -> {
      // Check that neither operand contains a time_slice expression
      use <- bool.guard(
        when: contains_time_slice(left) || contains_time_slice(right),
        return: Error(errors.CQLResolverError(
          msg: "time_slice cannot be used as an operand. It must be the entire expression.",
          context: errors.empty_context(),
        )),
      )
      Ok(GoodOverTotal(left, right))
    }
    ast.TimeSliceExpr(spec) ->
      Ok(TimeSlice(
        comparator: spec.comparator,
        interval_in_seconds: float.truncate(spec.interval_seconds),
        threshold: spec.threshold,
        query: spec.query,
      ))
    _ ->
      Error(errors.CQLResolverError(
        msg: "Invalid expression. Expected a top level division operator or time_slice.",
        context: errors.empty_context(),
      ))
  }
}

/// Checks if an expression contains a time_slice expression anywhere.
fn contains_time_slice(exp: Exp) -> Bool {
  case exp {
    ast.TimeSliceExpr(_) -> True
    ast.OperatorExpr(left, right, _) ->
      contains_time_slice(left) || contains_time_slice(right)
    ast.Primary(ast.PrimaryExp(inner)) -> contains_time_slice(inner)
    ast.Primary(ast.PrimaryWord(_)) -> False
  }
}
