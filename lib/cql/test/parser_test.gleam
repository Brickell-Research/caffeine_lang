import cql/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Sub,
  find_rightmost_operator_at_level, is_balanced_parens, is_last_char, parse_expr,
}
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit
import test_helpers.{
  exp_op_cont, parens, prim_word, simple_exp_op_cont, simple_op_cont,
}

pub fn parse_expr_parses_test() {
  describe("parse_expr", fn() {
    it("should parse a simple parenthesized word", fn() {
      parse_expr("(A)")
      |> gleeunit.equal(Ok(ExpContainer(parens(prim_word("A")))))
    })

    it("should parse a double parenthesized word", fn() {
      parse_expr("((A))")
      |> gleeunit.equal(Ok(ExpContainer(parens(parens(prim_word("A"))))))
    })

    it("should parse a simple addition expression", fn() {
      parse_expr("A + B")
      |> gleeunit.equal(Ok(simple_exp_op_cont("A", "B", Add)))
    })

    it("should parse a simple subtraction expression", fn() {
      parse_expr("A - B")
      |> gleeunit.equal(Ok(simple_exp_op_cont("A", "B", Sub)))
    })

    it("should parse a simple multiplication expression", fn() {
      parse_expr("A * B")
      |> gleeunit.equal(Ok(simple_exp_op_cont("A", "B", Mul)))
    })

    it("should parse a simple division expression", fn() {
      parse_expr("A / B")
      |> gleeunit.equal(Ok(simple_exp_op_cont("A", "B", Div)))
    })

    it(
      "should parse an expression with order of precedence using parentheses",
      fn() {
        parse_expr("(A + B) / C")
        |> gleeunit.equal(
          Ok(exp_op_cont(
            parens(simple_op_cont("A", "B", Add)),
            prim_word("C"),
            Div,
          )),
        )
      },
    )

    it("should parse a complex nested parentheses expression", fn() {
      let lhs =
        parens(OperatorExpr(
          parens(simple_op_cont("A", "B", Add)),
          prim_word("C"),
          Mul,
        ))

      let rhs =
        parens(OperatorExpr(
          prim_word("D"),
          parens(simple_op_cont("E", "F", Add)),
          Sub,
        ))
      parse_expr("((A + B) * C) / (D - (E + F))")
      |> gleeunit.equal(Ok(exp_op_cont(lhs, rhs, Div)))
    })

    it("should parse an expression with mixed operators precedence", fn() {
      parse_expr("A * B + C / D - E")
      |> gleeunit.equal(
        Ok(
          ExpContainer(OperatorExpr(
            simple_op_cont("A", "B", Mul),
            OperatorExpr(simple_op_cont("C", "D", Div), prim_word("E"), Sub),
            Add,
          )),
        ),
      )
    })

    it("should parse a deeply nested expression", fn() {
      parse_expr("(A + (B * (C - D)))")
      |> gleeunit.equal(
        Ok(
          ExpContainer(
            parens(OperatorExpr(
              prim_word("A"),
              parens(OperatorExpr(
                prim_word("B"),
                parens(simple_op_cont("C", "D", Sub)),
                Mul,
              )),
              Add,
            )),
          ),
        ),
      )
    })

    it("should parse a complex division expression", fn() {
      parse_expr("(X + Y * Z) / (A - B + C)")
      |> gleeunit.equal(
        Ok(exp_op_cont(
          parens(OperatorExpr(
            prim_word("X"),
            simple_op_cont("Y", "Z", Mul),
            Add,
          )),
          parens(OperatorExpr(
            simple_op_cont("A", "B", Sub),
            prim_word("C"),
            Add,
          )),
          Div,
        )),
      )
    })
  })
}

pub fn is_balanced_parens_test() {
  describe("is_balanced_parens", fn() {
    it("should return true for an empty string", fn() {
      is_balanced_parens("", 0, 0)
      |> gleeunit.be_true
    })

    it("should return true for balanced parentheses", fn() {
      is_balanced_parens("()", 0, 0)
      |> gleeunit.be_true
    })

    it("should return false for unbalanced parentheses", fn() {
      is_balanced_parens("(()))", 0, 0)
      |> gleeunit.be_false
    })

    it("should return true for complex balanced parentheses", fn() {
      is_balanced_parens("(a(b)(c)((())))", 11, 4)
      |> gleeunit.be_true
    })
  })
}

pub fn find_rightmost_operator_at_level_test() {
  describe("find_rightmost_operator_at_level", fn() {
    describe("success cases", fn() {
      it("should find the rightmost division operator", fn() {
        let actual =
          find_rightmost_operator_at_level("(A + B) / C", "/", 0, 0, -1)
        let expected = Ok(#("(A + B)", "C"))
        actual |> gleeunit.equal(expected)
      })

      it("should find the rightmost multiplication operator", fn() {
        let actual =
          find_rightmost_operator_at_level("(A - B) / D * C", "*", 0, 0, -1)
        let expected = Ok(#("(A - B) / D", "C"))
        actual |> gleeunit.equal(expected)
      })

      it("should find the rightmost subtraction operator", fn() {
        let actual =
          find_rightmost_operator_at_level("A - B / (D * C)", "-", 0, 0, -1)
        let expected = Ok(#("A", "B / (D * C)"))
        actual |> gleeunit.equal(expected)
      })
    })

    describe("error cases", fn() {
      it(
        "should return an error when operator is not found at the top level",
        fn() {
          let actual =
            find_rightmost_operator_at_level("(A + B) / C", "+", 0, 0, -1)
          actual |> gleeunit.be_error
        },
      )
    })
  })
}

pub fn is_last_char_test() {
  describe("is_last_char", fn() {
    it("should return true for empty string at index 0", fn() {
      is_last_char("", 0)
      |> gleeunit.be_true
    })

    it("should return true for single character string at index 0", fn() {
      is_last_char("a", 0)
      |> gleeunit.be_true
    })

    it("should return false when index is not the last character", fn() {
      is_last_char("()", 0)
      |> gleeunit.be_false
    })

    it("should return false for negative index", fn() {
      is_last_char("(()))", -1)
      |> gleeunit.be_false
    })

    it("should return false for index beyond string length", fn() {
      is_last_char("(()))", 100)
      |> gleeunit.be_false
    })

    it("should return true when index is the last character", fn() {
      is_last_char("(a(b)(c)((())))", 14)
      |> gleeunit.be_true
    })
  })
}
