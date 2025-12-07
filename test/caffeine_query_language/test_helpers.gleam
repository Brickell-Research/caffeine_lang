import caffeine_query_language/parser.{
  ExpContainer, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Word,
  is_last_char, parse_expr,
}
import caffeine_query_language/resolver.{resolve_primitives}
import gleeunit/should

pub fn prim_word(word: String) -> parser.Exp {
  let expected_word = Word(word)
  let expected_primary = PrimaryWord(expected_word)
  Primary(expected_primary)
}

pub fn parens(inner_exp: parser.Exp) -> parser.Exp {
  Primary(PrimaryExp(inner_exp))
}

pub fn exp_op_cont(
  numerator: parser.Exp,
  denominator: parser.Exp,
  op: parser.Operator,
) -> parser.ExpContainer {
  ExpContainer(OperatorExpr(numerator, denominator, op))
}

pub fn simple_op_cont(
  num: String,
  den: String,
  op: parser.Operator,
) -> parser.Exp {
  OperatorExpr(prim_word(num), prim_word(den), op)
}

pub fn simple_exp_op_cont(
  num: String,
  den: String,
  op: parser.Operator,
) -> parser.ExpContainer {
  ExpContainer(simple_op_cont(num, den, op))
}

pub fn parse_then_resolve_primitives(
  expr: String,
) -> Result(resolver.Primitives, String) {
  let assert Ok(parsed) = parse_expr(expr)

  resolve_primitives(parsed)
}

pub fn assert_invalid_expression(expr: String) {
  parse_then_resolve_primitives(expr)
  |> should.equal(Error("Invalid expression"))
}

pub fn assert_last_char(input: String, index: Int, expected: Bool) {
  is_last_char(input, index)
  |> should.equal(expected)
}
