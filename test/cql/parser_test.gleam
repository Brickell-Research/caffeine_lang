import caffeine_lang/cql/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord,
  Sub, Word,
}
import startest.{describe, it}
import startest/expect

pub fn cql_parser_tests() {
  describe("CQL Parser", [
    describe("parse_expr", [
      it("parses simple parenthesized word", fn() {
        let input = "(A)"

        let expected_word = Word("A")
        let expected_primary = PrimaryWord(expected_word)
        let inner_expected_exp = Primary(expected_primary)
        let expected_exp = Ok(ExpContainer(Primary(PrimaryExp(inner_expected_exp))))

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses simple double parenthesized word", fn() {
        let input = "((A))"

        let expected_word = Word("A")
        let expected_primary = PrimaryWord(expected_word)
        let inner_expected_exp = Primary(expected_primary)
        let second_innerexpected_exp = Primary(PrimaryExp(inner_expected_exp))
        let expected_exp =
          Ok(ExpContainer(Primary(PrimaryExp(second_innerexpected_exp))))

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses simple addition expression", fn() {
        let input = "A + B"

        let expected_word_a = Word("A")
        let expected_word_b = Word("B")

        let expected_primary_a = Primary(PrimaryWord(expected_word_a))
        let expected_primary_b = Primary(PrimaryWord(expected_word_b))

        let expected_exp =
          Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Add)))

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses simple subtraction expression", fn() {
        let input = "A - B"

        let expected_word_a = Word("A")
        let expected_word_b = Word("B")

        let expected_primary_a = Primary(PrimaryWord(expected_word_a))
        let expected_primary_b = Primary(PrimaryWord(expected_word_b))

        let expected_exp =
          Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Sub)))

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses simple multiplication expression", fn() {
        let input = "A * B"

        let expected_word_a = Word("A")
        let expected_word_b = Word("B")

        let expected_primary_a = Primary(PrimaryWord(expected_word_a))
        let expected_primary_b = Primary(PrimaryWord(expected_word_b))

        let expected_exp =
          Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Mul)))

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses simple division expression", fn() {
        let input = "A / B"

        let expected_word_a = Word("A")
        let expected_word_b = Word("B")

        let expected_primary_a = Primary(PrimaryWord(expected_word_a))
        let expected_primary_b = Primary(PrimaryWord(expected_word_b))

        let expected_exp =
          Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Div)))

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses expression with order of precedence using parentheses", fn() {
        let input = "(A + B) / C"

        let expected_word_a = Word("A")
        let expected_word_b = Word("B")
        let expected_word_c = Word("C")

        let expected_primary_a = Primary(PrimaryWord(expected_word_a))
        let expected_primary_b = Primary(PrimaryWord(expected_word_b))
        let expected_primary_c = Primary(PrimaryWord(expected_word_c))

        let expected_exp =
          Ok(
            ExpContainer(OperatorExpr(
              Primary(
                PrimaryExp(OperatorExpr(expected_primary_a, expected_primary_b, Add)),
              ),
              expected_primary_c,
              Div,
            )),
          )

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses expression with order of precedence without parentheses", fn() {
        let input = "A + B / C"

        let expected_word_a = Word("A")
        let expected_word_b = Word("B")
        let expected_word_c = Word("C")

        let expected_primary_a = Primary(PrimaryWord(expected_word_a))
        let expected_primary_b = Primary(PrimaryWord(expected_word_b))
        let expected_primary_c = Primary(PrimaryWord(expected_word_c))

        let expected_exp =
          Ok(
            ExpContainer(OperatorExpr(
              expected_primary_a,
              OperatorExpr(expected_primary_b, expected_primary_c, Div),
              Add,
            )),
          )

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses complex nested parentheses", fn() {
        let input = "((A + B) * C) / (D - (E + F))"

        let expected_exp =
          Ok(
            ExpContainer(OperatorExpr(
              Primary(
                PrimaryExp(OperatorExpr(
                  Primary(
                    PrimaryExp(OperatorExpr(
                      Primary(PrimaryWord(Word("A"))),
                      Primary(PrimaryWord(Word("B"))),
                      Add,
                    )),
                  ),
                  Primary(PrimaryWord(Word("C"))),
                  Mul,
                )),
              ),
              Primary(
                PrimaryExp(OperatorExpr(
                  Primary(PrimaryWord(Word("D"))),
                  Primary(
                    PrimaryExp(OperatorExpr(
                      Primary(PrimaryWord(Word("E"))),
                      Primary(PrimaryWord(Word("F"))),
                      Add,
                    )),
                  ),
                  Sub,
                )),
              ),
              Div,
            )),
          )

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses mixed operators with precedence", fn() {
        let input = "A * B + C / D - E"

        let expected_exp =
          Ok(
            ExpContainer(OperatorExpr(
              OperatorExpr(
                Primary(PrimaryWord(Word("A"))),
                Primary(PrimaryWord(Word("B"))),
                Mul,
              ),
              OperatorExpr(
                OperatorExpr(
                  Primary(PrimaryWord(Word("C"))),
                  Primary(PrimaryWord(Word("D"))),
                  Div,
                ),
                Primary(PrimaryWord(Word("E"))),
                Sub,
              ),
              Add,
            )),
          )

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses deeply nested expression", fn() {
        let input = "(A + (B * (C - D)))"

        let expected_exp =
          Ok(
            ExpContainer(
              Primary(
                PrimaryExp(OperatorExpr(
                  Primary(PrimaryWord(Word("A"))),
                  Primary(
                    PrimaryExp(OperatorExpr(
                      Primary(PrimaryWord(Word("B"))),
                      Primary(
                        PrimaryExp(OperatorExpr(
                          Primary(PrimaryWord(Word("C"))),
                          Primary(PrimaryWord(Word("D"))),
                          Sub,
                        )),
                      ),
                      Mul,
                    )),
                  ),
                  Add,
                )),
              ),
            ),
          )

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
      it("parses complex division expression", fn() {
        let input = "(X + Y * Z) / (A - B + C)"

        let expected_exp =
          Ok(
            ExpContainer(OperatorExpr(
              Primary(
                PrimaryExp(OperatorExpr(
                  Primary(PrimaryWord(Word("X"))),
                  OperatorExpr(
                    Primary(PrimaryWord(Word("Y"))),
                    Primary(PrimaryWord(Word("Z"))),
                    Mul,
                  ),
                  Add,
                )),
              ),
              Primary(
                PrimaryExp(OperatorExpr(
                  OperatorExpr(
                    Primary(PrimaryWord(Word("A"))),
                    Primary(PrimaryWord(Word("B"))),
                    Sub,
                  ),
                  Primary(PrimaryWord(Word("C"))),
                  Add,
                )),
              ),
              Div,
            )),
          )

        let actual = parser.parse_expr(input)

        expect.to_equal(actual, expected_exp)
      }),
    ]),
  ])
}
