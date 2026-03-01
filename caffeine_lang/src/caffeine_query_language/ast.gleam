/// Marker type for parsed CQL expressions (pre-substitution).
pub type CqlParsed

/// Marker type for substituted CQL expressions (post-substitution).
pub type Substituted

/// Arithmetic operators supported in CQL expressions.
pub type Operator {
  Add
  Sub
  Mul
  Div
}

/// Comparators for time slice expressions.
pub type Comparator {
  LessThan
  LessThanOrEqualTo
  GreaterThan
  GreaterThanOrEqualTo
}

/// Time slice specification containing query, comparator, threshold, and interval.
pub type TimeSliceExp {
  TimeSliceExp(
    query: String,
    comparator: Comparator,
    threshold: Float,
    interval_seconds: Float,
  )
}

/// An expression in the CQL AST, either an operator expression or a primary.
/// The phantom `state` parameter tracks whether words have been substituted.
pub type Exp(state) {
  TimeSliceExpr(spec: TimeSliceExp)
  OperatorExpr(
    numerator: Exp(state),
    denominator: Exp(state),
    operator: Operator,
  )
  Primary(primary: Primary(state))
}

/// A primary expression, either a word (identifier) or a parenthesized expression.
/// The phantom `state` parameter mirrors the parent Exp's state.
pub type Primary(state) {
  PrimaryWord(word: Word)
  PrimaryExp(exp: Exp(state))
}

/// A word (identifier) in the expression.
pub type Word {
  Word(value: String)
}
