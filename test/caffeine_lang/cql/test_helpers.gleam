import caffeine_lang/cql/parser.{
  ExpContainer, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Word,
}

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
