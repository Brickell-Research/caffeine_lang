import deps/cql/parser.{Add, Mul, OperatorExpr, Sub, parse_expr}
import deps/cql/resolver.{GoodOverTotal, resolve_primitives}
import deps/cql/test_helpers.{parens, prim_word, simple_op_cont}
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit

fn parse_then_resolve_primitives(
  expr: String,
) -> Result(resolver.Primitives, String) {
  let assert Ok(parsed) = parse_expr(expr)

  resolve_primitives(parsed)
}

pub fn resolve_primitives_test() {
  describe("resolve_primitives", fn() {
    describe("valid expressions", fn() {
      it("should resolve a simple good over bad expression", fn() {
        parse_then_resolve_primitives("A / B")
        |> gleeunit.equal(Ok(GoodOverTotal(prim_word("A"), prim_word("B"))))
      })

      it(
        "should resolve a moderately more complex good over bad expression",
        fn() {
          parse_then_resolve_primitives("(A + B) / C")
          |> gleeunit.equal(
            Ok(GoodOverTotal(
              parens(simple_op_cont("A", "B", Add)),
              prim_word("C"),
            )),
          )
        },
      )

      it("should resolve a nested and complex good over bad expression", fn() {
        parse_then_resolve_primitives("((A - G) + B) / (C + (D + E) * F)")
        |> gleeunit.equal(
          Ok(GoodOverTotal(
            parens(OperatorExpr(
              parens(simple_op_cont("A", "G", Sub)),
              prim_word("B"),
              Add,
            )),
            parens(OperatorExpr(
              prim_word("C"),
              OperatorExpr(
                parens(simple_op_cont("D", "E", Add)),
                prim_word("F"),
                Mul,
              ),
              Add,
            )),
          )),
        )
      })
    })

    describe("invalid expressions", fn() {
      it("should return an error for a simple expression", fn() {
        parse_then_resolve_primitives("A + B")
        |> gleeunit.equal(Error("Invalid expression"))
      })

      it(
        "should return an error for a moderately more complex expression",
        fn() {
          parse_then_resolve_primitives("A + B / C + D")
          |> gleeunit.equal(Error("Invalid expression"))
        },
      )

      it("should return an error for a nested and complex expression", fn() {
        parse_then_resolve_primitives("((A + B) - E) / C + D")
        |> gleeunit.equal(Error("Invalid expression"))
      })
    })
  })
}
