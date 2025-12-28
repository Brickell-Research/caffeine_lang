import caffeine_lang/common/errors.{type CompilationError}
import caffeine_query_language/parser.{
  type Exp, type ExpContainer, Div, ExpContainer, OperatorExpr, TimeSliceExpr,
}
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

/// Set of valid comparison operators.
/// FUTURE: possible we may want a good ol' '==' 🤷‍♂️. Not yet atleast and YAGNI.
pub type Comparator {
  // <
  LessThan
  // <=
  LessThanOrEqualTo
  // >
  GreaterThan
  // >=
  GreaterThanOrEqualTo
}

/// Converst a comparator to a string
@internal
pub fn comparator_to_string(comparator: Comparator) {
  case comparator {
    LessThan -> "\"<\""
    LessThanOrEqualTo -> "\"<=\""
    GreaterThan -> "\">\""
    GreaterThanOrEqualTo -> "\">=\""
  }
}

/// Converts a parser Comparator to a resolver Comparator.
fn convert_comparator(comp: parser.Comparator) -> Comparator {
  case comp {
    parser.LessThan -> LessThan
    parser.LessThanOrEqualTo -> LessThanOrEqualTo
    parser.GreaterThan -> GreaterThan
    parser.GreaterThanOrEqualTo -> GreaterThanOrEqualTo
  }
}

/// Resolves a parsed CQL expression into a primitive type.
/// Supports GoodOverTotal (division at the top level) and TimeSlice.
/// Returns an error if the expression doesn't match a known primitive pattern.
@internal
pub fn resolve_primitives(
  exp_container: ExpContainer,
) -> Result(Primitives, CompilationError) {
  case exp_container {
    ExpContainer(exp) ->
      case exp {
        OperatorExpr(left, right, Div) -> {
          // Check that neither operand contains a time_slice expression
          case contains_time_slice(left) || contains_time_slice(right) {
            True ->
              Error(errors.CQLResolverError(
                msg: "time_slice cannot be used as an operand. It must be the entire expression.",
              ))
            False -> Ok(GoodOverTotal(left, right))
          }
        }
        TimeSliceExpr(spec) ->
          Ok(TimeSlice(
            comparator: convert_comparator(spec.comparator),
            interval_in_seconds: float.truncate(spec.interval_seconds),
            threshold: spec.threshold,
            query: spec.query,
          ))
        _ ->
          Error(errors.CQLResolverError(
            msg: "Invalid expression. Expected a top level division operator or time_slice.",
          ))
      }
  }
}

/// Checks if an expression contains a time_slice expression anywhere.
fn contains_time_slice(exp: Exp) -> Bool {
  case exp {
    TimeSliceExpr(_) -> True
    OperatorExpr(left, right, _) ->
      contains_time_slice(left) || contains_time_slice(right)
    parser.Primary(parser.PrimaryExp(inner)) -> contains_time_slice(inner)
    parser.Primary(parser.PrimaryWord(_)) -> False
  }
}
