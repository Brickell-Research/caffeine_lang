import caffeine_lang/cql/parser.{
  Add, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Sub, Word,
  parse_expr,
}
import caffeine_lang/cql/resolver.{GoodOverTotal, resolve_primitives}
import startest/expect

pub fn resolve_primitives_good_over_total_test() {
  let input = "A / B"

  let expected =
    Ok(GoodOverTotal(
      Primary(PrimaryWord(Word("A"))),
      Primary(PrimaryWord(Word("B"))),
    ))

  let assert Ok(parsed) = parse_expr(input)
  let actual = resolve_primitives(parsed)

  expect.to_equal(actual, expected)
}

pub fn resolve_primitives_good_over_total_moderately_more_complex_test() {
  let input = "A + B / C"

  let expected =
    Ok(GoodOverTotal(
      OperatorExpr(
        Primary(PrimaryWord(Word("A"))),
        Primary(PrimaryWord(Word("B"))),
        Add,
      ),
      Primary(PrimaryWord(Word("C"))),
    ))

  let assert Ok(parsed) = parse_expr(input)
  let actual = resolve_primitives(parsed)

  assert actual == expected
}

pub fn resolve_primitives_invalid_test() {
  let input = "A + B"

  let expected = Error("Invalid expression")

  let assert Ok(parsed) = parse_expr(input)
  let actual = resolve_primitives(parsed)

  expect.to_equal(actual, expected)
}

pub fn resolve_complex_good_over_total_test() {
  let input = "(A - G) + B / (C + (D + E) * F)"

  let expected =
    Ok(GoodOverTotal(
      OperatorExpr(
        Primary(
          PrimaryExp(OperatorExpr(
            Primary(PrimaryWord(Word("A"))),
            Primary(PrimaryWord(Word("G"))),
            Sub,
          )),
        ),
        Primary(PrimaryWord(Word("B"))),
        Add,
      ),
      Primary(
        PrimaryExp(OperatorExpr(
          Primary(PrimaryWord(Word("C"))),
          OperatorExpr(
            Primary(
              PrimaryExp(OperatorExpr(
                Primary(PrimaryWord(Word("D"))),
                Primary(PrimaryWord(Word("E"))),
                Add,
              )),
            ),
            Primary(PrimaryWord(Word("F"))),
            Mul,
          ),
          Add,
        )),
      ),
    ))

  let assert Ok(parsed) = parse_expr(input)
  let actual = resolve_primitives(parsed)

  expect.to_equal(actual, expected)
}
