import caffeine_query_language/errors.{CQLResolverError}
import caffeine_query_language/parser.{Add, Mul, OperatorExpr, Sub}
import caffeine_query_language/resolver.{
  GoodOverTotal, GreaterThan, GreaterThanOrEqualTo, LessThan, TimeSlice,
}
import caffeine_query_language/test_helpers.{
  parens, parse_then_resolve_primitives, prim_word, simple_op_cont,
}
import gleam/list
import gleeunit/should

// ==== resolve_primitives Tests ====
// good_over_total:
// * ✅ simple good over total (A / B)
// * ✅ moderately complex good over total ((A + B) / C)
// * ✅ nested and complex good over total
// * ✅ error for simple non-division expression
// * ✅ error for moderately complex non-division expression
// * ✅ error for nested and complex non-division expression
// time_slice valid (see resolve_time_slice_valid_test):
// * ✅ time_slice(Query > 1000000 per 10s) - basic
// * ✅ time_slice(Query >= 100 per 60s) - different comparator
// * ✅ time_slice(Query < 99.5 per 5m) - decimal threshold, minutes
// time_slice invalid (see resolve_time_slice_invalid_test):
// * ✅ time_slice(Query > 100 per 10s) + B - keyword not at top level
// * ✅ A + time_slice(Query > 100 per 10s) - keyword not at top level
// * ✅ (time_slice(Query > 100 per 10s)) - wrapped in parens
// * ✅ time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s) - multiple keywords

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
        "Invalid expression. Expected a top level division operator or time_slice.",
      )),
    ),
    // error for moderately complex non-division expression
    #(
      "A + B / C + D",
      Error(CQLResolverError(
        "Invalid expression. Expected a top level division operator or time_slice.",
      )),
    ),
    // error for nested and complex non-division expression
    #(
      "((A + B) - E) / C + D",
      Error(CQLResolverError(
        "Invalid expression. Expected a top level division operator or time_slice.",
      )),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    parse_then_resolve_primitives(input) |> should.equal(expected)
  })
}

// ==== time_slice valid (resolves to TimeSlice primitive) Tests ====

pub fn resolve_time_slice_valid_test() {
  [
    // time_slice(Query > 1000000 per 10s) - basic
    #(
      "time_slice(Query > 1000000 per 10s)",
      Ok(TimeSlice(
        comparator: GreaterThan,
        interval_in_seconds: 10,
        threshold: 1_000_000.0,
        query: "Query",
      )),
    ),
    // time_slice(Query >= 100 per 60s) - different comparator
    #(
      "time_slice(Query >= 100 per 60s)",
      Ok(TimeSlice(
        comparator: GreaterThanOrEqualTo,
        interval_in_seconds: 60,
        threshold: 100.0,
        query: "Query",
      )),
    ),
    // time_slice(Query < 99.5 per 5m) - decimal threshold, minutes
    #(
      "time_slice(Query < 99.5 per 5m)",
      Ok(TimeSlice(
        comparator: LessThan,
        interval_in_seconds: 300,
        threshold: 99.5,
        query: "Query",
      )),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    parse_then_resolve_primitives(input) |> should.equal(expected)
  })
}

// ==== time_slice invalid (should error) Tests ====

pub fn resolve_time_slice_invalid_test() {
  [
    // time_slice(Query > 100 per 10s) + B - keyword not at top level
    "time_slice(Query > 100 per 10s) + B",
    // A + time_slice(Query > 100 per 10s) - keyword not at top level
    "A + time_slice(Query > 100 per 10s)",
    // (time_slice(Query > 100 per 10s)) - wrapped in parens
    "(time_slice(Query > 100 per 10s))",
    // time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s) - multiple keywords
    "time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s)",
  ]
  |> list.each(fn(input) {
    parse_then_resolve_primitives(input) |> should.be_error
  })
}
