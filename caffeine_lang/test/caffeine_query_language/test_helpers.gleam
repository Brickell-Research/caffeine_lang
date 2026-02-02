import caffeine_lang/errors.{type CompilationError}
import caffeine_query_language/ast.{
  type Exp, type Operator, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Word,
}
import caffeine_query_language/parser.{parse_expr}
import caffeine_query_language/resolver.{resolve_primitives}

/// Creates a Primary Word expression from a string.
pub fn prim_word(word: String) -> Exp {
  let expected_word = Word(word)
  let expected_primary = PrimaryWord(expected_word)
  Primary(expected_primary)
}

/// Wraps an expression in parentheses (PrimaryExp).
pub fn parens(inner_exp: Exp) -> Exp {
  Primary(PrimaryExp(inner_exp))
}

/// Creates an operator expression from two word strings.
pub fn simple_op_cont(num: String, den: String, op: Operator) -> Exp {
  OperatorExpr(prim_word(num), prim_word(den), op)
}

/// Creates an Exp with a simple operator expression from two word strings.
pub fn simple_exp_op(num: String, den: String, op: Operator) -> Exp {
  simple_op_cont(num, den, op)
}

/// Creates an operator expression from two sub-expressions.
pub fn exp_op(numerator: Exp, denominator: Exp, op: Operator) -> Exp {
  OperatorExpr(numerator, denominator, op)
}

/// Parses an expression string and resolves it to primitives.
pub fn parse_then_resolve_primitives(
  expr: String,
) -> Result(resolver.Primitives, CompilationError) {
  let assert Ok(parsed) = parse_expr(expr)
  resolve_primitives(parsed)
}
