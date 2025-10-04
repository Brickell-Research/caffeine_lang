import caffeine_lang/cql/parser.{
  Add, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Sub, Word,
  parse_expr,
}
import caffeine_lang/cql/resolver.{GoodOverTotal, resolve_primitives}
import gleeunit/should

pub fn resolve_primitives_resolves_simple_good_over_total_expression_test() {
        let input = "A / B"

        let expected =
          Ok(GoodOverTotal(
            Primary(PrimaryWord(Word("A"))),
            Primary(PrimaryWord(Word("B"))),
          ))

        let assert Ok(parsed) = parse_expr(input)
        let actual = resolve_primitives(parsed)

        actual
        |> should.equal(expected)
}

pub fn resolve_primitives_resolves_moderately_complex_good_over_total_expression_test() {
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

        actual
        |> should.equal(expected)
}

pub fn resolve_primitives_returns_error_for_invalid_expression_test() {
        let input = "A + B"

        let expected = Error("Invalid expression")

        let assert Ok(parsed) = parse_expr(input)
        let actual = resolve_primitives(parsed)

        actual
        |> should.equal(expected)
}

pub fn resolve_primitives_resolves_complex_nested_good_over_total_expression_test() {
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

        actual
        |> should.equal(expected)
}
