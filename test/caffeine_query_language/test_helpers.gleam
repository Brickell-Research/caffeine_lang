import caffeine_lang/common/errors.{type CompilationError}
import caffeine_query_language/parser.{parse_expr}
import caffeine_query_language/resolver.{resolve_primitives}

/// Creates a Primary Word expression from a string.
pub fn prim_word(word: String) -> parser.Exp {
  let expected_word = parser.Word(word)
  let expected_primary = parser.PrimaryWord(expected_word)
  parser.Primary(expected_primary)
}

/// Wraps an expression in parentheses (PrimaryExp).
pub fn parens(inner_exp: parser.Exp) -> parser.Exp {
  parser.Primary(parser.PrimaryExp(inner_exp))
}

/// Creates an ExpContainer with an operator expression.
pub fn exp_op_cont(
  numerator: parser.Exp,
  denominator: parser.Exp,
  op: parser.Operator,
) -> parser.ExpContainer {
  parser.ExpContainer(parser.OperatorExpr(numerator, denominator, op))
}

/// Creates an operator expression from two word strings.
pub fn simple_op_cont(
  num: String,
  den: String,
  op: parser.Operator,
) -> parser.Exp {
  parser.OperatorExpr(prim_word(num), prim_word(den), op)
}

/// Creates an ExpContainer with a simple operator expression from two word strings.
pub fn simple_exp_op_cont(
  num: String,
  den: String,
  op: parser.Operator,
) -> parser.ExpContainer {
  parser.ExpContainer(simple_op_cont(num, den, op))
}

/// Parses an expression string and resolves it to primitives.
pub fn parse_then_resolve_primitives(
  expr: String,
) -> Result(resolver.Primitives, CompilationError) {
  let assert Ok(parsed) = parse_expr(expr)
  resolve_primitives(parsed)
}
