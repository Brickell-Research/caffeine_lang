import caffeine_lang/cql/parser.{
  Add, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord, Sub, Word,
  parse_expr,
}
import caffeine_lang/cql/resolver.{GoodOverTotal, resolve_primitives}
import startest.{describe, it}
import startest/expect

pub fn cql_resolver_tests() {
  describe("CQL Resolver", [
    describe("resolve_primitives", [
      it("resolves simple good over total expression", fn() {
        let input = "A / B"

        let expected =
          Ok(GoodOverTotal(
            Primary(PrimaryWord(Word("A"))),
            Primary(PrimaryWord(Word("B"))),
          ))

        let assert Ok(parsed) = parse_expr(input)
        let actual = resolve_primitives(parsed)

        expect.to_equal(actual, expected)
      }),
      it("resolves moderately complex good over total expression", fn() {
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

        expect.to_equal(actual, expected)
      }),
      it("returns error for invalid expression", fn() {
        let input = "A + B"

        let expected = Error("Invalid expression")

        let assert Ok(parsed) = parse_expr(input)
        let actual = resolve_primitives(parsed)

        expect.to_equal(actual, expected)
      }),
      it("resolves complex nested good over total expression", fn() {
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
      }),
    ]),
  ])
}
