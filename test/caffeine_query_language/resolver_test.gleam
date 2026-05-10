import caffeine_lang/errors
import caffeine_query_language/ast
import caffeine_query_language/resolver
import caffeine_query_language/test_helpers as cql_test_helpers
import test_helpers

const parens = cql_test_helpers.parens

const parse_then_resolve_primitives = cql_test_helpers.parse_then_resolve_primitives

const prim_word = cql_test_helpers.prim_word

const simple_op_cont = cql_test_helpers.simple_op_cont

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
    parens(ast.OperatorExpr(
      parens(simple_op_cont("A", "G", ast.Sub)),
      prim_word("B"),
      ast.Add,
    ))
  let rhs_complex =
    parens(ast.OperatorExpr(
      prim_word("C"),
      ast.OperatorExpr(
        parens(simple_op_cont("D", "E", ast.Add)),
        prim_word("F"),
        ast.Mul,
      ),
      ast.Add,
    ))

  [
    // simple good over total (A / B)
    #(
      "simple good over total (A / B)",
      "A / B",
      Ok(resolver.GoodOverTotal(prim_word("A"), prim_word("B"))),
    ),
    // moderately complex good over total ((A + B) / C)
    #(
      "moderately complex good over total ((A + B) / C)",
      "(A + B) / C",
      Ok(resolver.GoodOverTotal(
        parens(simple_op_cont("A", "B", ast.Add)),
        prim_word("C"),
      )),
    ),
    // nested and complex good over total
    #(
      "nested and complex good over total",
      "((A - G) + B) / (C + (D + E) * F)",
      Ok(resolver.GoodOverTotal(lhs_complex, rhs_complex)),
    ),
    // error for simple non-division expression
    #(
      "error for simple non-division expression",
      "A + B",
      Error(errors.CQLResolverError(
        msg: "Invalid expression. Expected a top level division operator or time_slice.",
        context: errors.empty_context(),
      )),
    ),
    // error for moderately complex non-division expression
    #(
      "error for moderately complex non-division expression",
      "A + B / C + D",
      Error(errors.CQLResolverError(
        msg: "Invalid expression. Expected a top level division operator or time_slice.",
        context: errors.empty_context(),
      )),
    ),
    // error for nested and complex non-division expression
    #(
      "error for nested and complex non-division expression",
      "((A + B) - E) / C + D",
      Error(errors.CQLResolverError(
        msg: "Invalid expression. Expected a top level division operator or time_slice.",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(parse_then_resolve_primitives)
}

// ==== time_slice valid (resolves to TimeSlice primitive) Tests ====

pub fn resolve_time_slice_valid_test() {
  [
    // time_slice(Query > 1000000 per 10s) - basic
    #(
      "time_slice basic with >",
      "time_slice(Query > 1000000 per 10s)",
      Ok(resolver.TimeSlice(
        comparator: ast.GreaterThan,
        interval_in_seconds: 10,
        threshold: 1_000_000.0,
        query: "Query",
      )),
    ),
    // time_slice(Query >= 100 per 60s) - different comparator
    #(
      "time_slice different comparator >=",
      "time_slice(Query >= 100 per 60s)",
      Ok(resolver.TimeSlice(
        comparator: ast.GreaterThanOrEqualTo,
        interval_in_seconds: 60,
        threshold: 100.0,
        query: "Query",
      )),
    ),
    // time_slice(Query < 99.5 per 5m) - decimal threshold, minutes
    #(
      "time_slice decimal threshold, minutes",
      "time_slice(Query < 99.5 per 5m)",
      Ok(resolver.TimeSlice(
        comparator: ast.LessThan,
        interval_in_seconds: 300,
        threshold: 99.5,
        query: "Query",
      )),
    ),
  ]
  |> test_helpers.table_test_1(parse_then_resolve_primitives)
}

// ==== time_slice invalid (should error) Tests ====

pub fn resolve_time_slice_invalid_test() {
  let time_slice_operand_error =
    Error(errors.CQLResolverError(
      msg: "time_slice cannot be used as an operand. It must be the entire expression.",
      context: errors.empty_context(),
    ))
  let not_division_or_time_slice_error =
    Error(errors.CQLResolverError(
      msg: "Invalid expression. Expected a top level division operator or time_slice.",
      context: errors.empty_context(),
    ))

  [
    // time_slice(Query > 100 per 10s) + B - keyword not at top level
    #(
      "keyword not at top level (left operand)",
      "time_slice(Query > 100 per 10s) + B",
      not_division_or_time_slice_error,
    ),
    // A + time_slice(Query > 100 per 10s) - keyword not at top level
    #(
      "keyword not at top level (right operand)",
      "A + time_slice(Query > 100 per 10s)",
      not_division_or_time_slice_error,
    ),
    // (time_slice(Query > 100 per 10s)) - wrapped in parens
    #(
      "wrapped in parens",
      "(time_slice(Query > 100 per 10s))",
      not_division_or_time_slice_error,
    ),
    // time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s) - multiple keywords
    #(
      "multiple keywords",
      "time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s)",
      time_slice_operand_error,
    ),
  ]
  |> test_helpers.table_test_1(parse_then_resolve_primitives)
}
