import caffeine_lang/cql/parser.{Add, Mul, OperatorExpr, Sub, parse_expr}
import caffeine_lang/cql/resolver.{GoodOverTotal, resolve_primitives}
import cql/test_helpers.{parens, prim_word, simple_op_cont}
import gleeunit/should

pub fn resolve_primitives_test() {
  // Simple good over bad
  let assert Ok(parsed) = parse_expr("A / B")

  resolve_primitives(parsed)
  |> should.equal(Ok(GoodOverTotal(prim_word("A"), prim_word("B"))))

  // Moderately more complex good over bad
  let assert Ok(parsed) = parse_expr("A + B / C")

  resolve_primitives(parsed)
  |> should.equal(
    Ok(GoodOverTotal(simple_op_cont("A", "B", Add), prim_word("C"))),
  )

  // Nested and complex good over bad
  let assert Ok(parsed) = parse_expr("(A - G) + B / (C + (D + E) * F)")

  resolve_primitives(parsed)
  |> should.equal(
    Ok(GoodOverTotal(
      OperatorExpr(parens(simple_op_cont("A", "G", Sub)), prim_word("B"), Add),
      parens(OperatorExpr(
        prim_word("C"),
        OperatorExpr(parens(simple_op_cont("D", "E", Add)), prim_word("F"), Mul),
        Add,
      )),
    )),
  )

  // Invalid expression, addition and no division
  let assert Ok(parsed) = parse_expr("A + B")

  resolve_primitives(parsed)
  |> should.equal(Error("Invalid expression"))

  // More complex invalid expression
  let assert Ok(parsed) = parse_expr("A + B / C + D")

  resolve_primitives(parsed)
  |> should.equal(Error("Invalid expression"))

  // Even more complex invalid expression
  let assert Ok(parsed) = parse_expr("((A + B) - E) / C + D")

  resolve_primitives(parsed)
  |> should.equal(Error("Invalid expression"))
}
