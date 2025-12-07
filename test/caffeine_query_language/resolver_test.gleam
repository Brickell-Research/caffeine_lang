import caffeine_query_language/parser.{Add, Mul, OperatorExpr, Sub}
import caffeine_query_language/resolver.{GoodOverTotal}
import caffeine_query_language/test_helpers.{
  assert_invalid_expression, parens, parse_then_resolve_primitives, prim_word,
  simple_op_cont,
}
import gleeunit/should

pub fn resolve_primitives_should_resolve_a_simple_good_over_bad_expression_test() {
  let lhs = prim_word("A")
  let rhs = prim_word("B")
  let expected = Ok(GoodOverTotal(lhs, rhs))

  let actual = parse_then_resolve_primitives("A / B")

  actual |> should.equal(expected)
}

pub fn resolve_primitives_should_resolve_a_moderately_more_complex_good_over_bad_expression_test() {
  let lhs = parens(simple_op_cont("A", "B", Add))
  let rhs = prim_word("C")
  let expected = Ok(GoodOverTotal(lhs, rhs))

  let actual = parse_then_resolve_primitives("(A + B) / C")

  actual |> should.equal(expected)
}

pub fn resolve_primitives_should_resolve_a_nested_and_complex_good_over_bad_expression_test() {
  let lhs =
    parens(OperatorExpr(
      parens(simple_op_cont("A", "G", Sub)),
      prim_word("B"),
      Add,
    ))
  let rhs =
    parens(OperatorExpr(
      prim_word("C"),
      OperatorExpr(parens(simple_op_cont("D", "E", Add)), prim_word("F"), Mul),
      Add,
    ))

  let expected = Ok(GoodOverTotal(lhs, rhs))

  let actual =
    parse_then_resolve_primitives("((A - G) + B) / (C + (D + E) * F)")

  actual |> should.equal(expected)
}

pub fn resolve_primitives_should_return_an_error_for_a_simple_expression_test() {
  assert_invalid_expression("A + B")
}

pub fn resolve_primitives_should_return_an_error_for_a_moderately_more_complex_expression_test() {
  assert_invalid_expression("A + B / C + D")
}

pub fn resolve_primitives_should_return_an_error_for_a_nested_and_complex_expression_test() {
  assert_invalid_expression("((A + B) - E) / C + D")
}
