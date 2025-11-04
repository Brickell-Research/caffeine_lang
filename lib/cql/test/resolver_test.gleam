import cql/parser.{Add, Mul, OperatorExpr, Sub, parse_expr}
import cql/resolver.{GoodOverTotal, resolve_primitives}
import gleeunit/should
import test_helpers.{parens, prim_word, simple_op_cont}

fn parse_then_resolve_primitives(
  expr: String,
) -> Result(resolver.Primitives, String) {
  let assert Ok(parsed) = parse_expr(expr)

  resolve_primitives(parsed)
}

pub fn resolve_primitives_test() {
  // ======== Valid Expressions ========
  // Simple good over bad
  parse_then_resolve_primitives("A / B")
  |> should.equal(Ok(GoodOverTotal(prim_word("A"), prim_word("B"))))

  // Moderately more complex good over bad
  parse_then_resolve_primitives("(A + B) / C")
  |> should.equal(
    Ok(GoodOverTotal(parens(simple_op_cont("A", "B", Add)), prim_word("C"))),
  )

  // Nested and complex good over bad
  parse_then_resolve_primitives("((A - G) + B) / (C + (D + E) * F)")
  |> should.equal(
    Ok(GoodOverTotal(
      parens(OperatorExpr(
        parens(simple_op_cont("A", "G", Sub)),
        prim_word("B"),
        Add,
      )),
      parens(OperatorExpr(
        prim_word("C"),
        OperatorExpr(parens(simple_op_cont("D", "E", Add)), prim_word("F"), Mul),
        Add,
      )),
    )),
  )

  // ======== Invalid Expressions ========
  // Invalid expression, addition and no division
  parse_then_resolve_primitives("A + B")
  |> should.equal(Error("Invalid expression"))

  // More complex invalid expression
  parse_then_resolve_primitives("A + B / C + D")
  |> should.equal(Error("Invalid expression"))

  // Even more complex invalid expression
  parse_then_resolve_primitives("((A + B) - E) / C + D")
  |> should.equal(Error("Invalid expression"))
}
