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
pub type Exp {
  TimeSliceExpr(spec: TimeSliceExp)
  OperatorExpr(numerator: Exp, denominator: Exp, operator: Operator)
  Primary(primary: Primary)
}

/// A primary expression, either a word (identifier) or a parenthesized expression.
pub type Primary {
  PrimaryWord(word: Word)
  PrimaryExp(exp: Exp)
}

/// A word (identifier) in the expression.
pub type Word {
  Word(value: String)
}
