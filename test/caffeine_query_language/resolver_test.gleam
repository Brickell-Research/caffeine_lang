import caffeine_query_language/errors.{CQLResolverError}
import caffeine_query_language/parser.{Add, Mul, OperatorExpr, Sub}
import caffeine_query_language/resolver.{GoodOverTotal}
import caffeine_query_language/test_helpers.{
  parens, parse_then_resolve_primitives, prim_word, simple_op_cont,
}
import gleam/list
import gleeunit/should

// ==== resolve_primitives Tests ====
// * ✅ simple good over total (A / B)
// * ✅ moderately complex good over total ((A + B) / C)
// * ✅ nested and complex good over total
// * ✅ error for simple non-division expression
// * ✅ error for moderately complex non-division expression
// * ✅ error for nested and complex non-division expression

pub fn resolve_primitives_test() {
  let lhs_complex =
    parens(OperatorExpr(
      parens(simple_op_cont("A", "G", Sub)),
      prim_word("B"),
      Add,
    ))
  let rhs_complex =
    parens(OperatorExpr(
      prim_word("C"),
      OperatorExpr(parens(simple_op_cont("D", "E", Add)), prim_word("F"), Mul),
      Add,
    ))

  [
    // simple good over total (A / B)
    #("A / B", Ok(GoodOverTotal(prim_word("A"), prim_word("B")))),
    // moderately complex good over total ((A + B) / C)
    #(
      "(A + B) / C",
      Ok(GoodOverTotal(parens(simple_op_cont("A", "B", Add)), prim_word("C"))),
    ),
    // nested and complex good over total
    #(
      "((A - G) + B) / (C + (D + E) * F)",
      Ok(GoodOverTotal(lhs_complex, rhs_complex)),
    ),
    // error for simple non-division expression
    #(
      "A + B",
      Error(CQLResolverError(
        "Invalid expression. Expected a top level division operator.",
      )),
    ),
    // error for moderately complex non-division expression
    #(
      "A + B / C + D",
      Error(CQLResolverError(
        "Invalid expression. Expected a top level division operator.",
      )),
    ),
    // error for nested and complex non-division expression
    #(
      "((A + B) - E) / C + D",
      Error(CQLResolverError(
        "Invalid expression. Expected a top level division operator.",
      )),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    parse_then_resolve_primitives(input) |> should.equal(expected)
  })
}
