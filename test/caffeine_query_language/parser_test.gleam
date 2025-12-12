import caffeine_query_language/parser.{
  Add, Div, ExpContainer, GreaterThan, GreaterThanOrEqualTo, LessThan,
  LessThanOrEqualTo, Mul, OperatorExpr, Primary, PrimaryWord, Sub, TimeSliceExp,
  TimeSliceExpr, Word, find_rightmost_operator_at_level, is_balanced_parens,
  is_last_char, parse_expr,
}
import caffeine_query_language/test_helpers.{
  exp_op_cont, parens, prim_word, simple_exp_op_cont, simple_op_cont,
}
import gleam/list
import gleeunit/should

// ==== parse_expr Tests ====
// general:
// * ✅ simple parenthesized word
// * ✅ double parenthesized word
// * ✅ simple addition
// * ✅ simple subtraction
// * ✅ simple multiplication
// * ✅ simple division
// * ✅ order of precedence with parentheses
// * ✅ complex nested parentheses
// * ✅ mixed operators precedence
// * ✅ deeply nested expression
// * ✅ complex division expression
// * ✅ time_slice with basic expression
// time_slice valid parsing (see time_slice_valid_parsing_test):
// * ✅ time_slice(Query > 1000000 per 10s) - basic with >
// * ✅ time_slice(Query < 500 per 30s) - with <
// * ✅ time_slice(Query >= 100 per 60s) - with >=
// * ✅ time_slice(Query <= 999 per 5s) - with <=
// * ✅ time_slice(avg:system.cpu > 80 per 300s) - realistic metric query
// * ✅ time_slice( Query > 100 per 10s ) - whitespace handling
// * ✅ time_slice(Query > 99.5 per 10s) - decimal threshold
// * ✅ time_slice(Query > 100 per 10m) - minutes interval
// * ✅ time_slice(Query > 100 per 1h) - hours interval
// * ✅ time_slice(Query > 100 per 1.5h) - decimal interval
// time_slice invalid inner syntax (see time_slice_invalid_syntax_test):
// * ✅ time_slice(Query > 100) - missing per <interval>
// * ✅ time_slice(Query 100 per 10s) - missing comparator
// * ✅ time_slice(> 100 per 10s) - missing query
// * ✅ time_slice(Query > per 10s) - missing threshold
// * ✅ time_slice(Query > 100 per) - missing interval
// * ✅ time_slice(Query > 100 per s) - invalid interval (no number)
// * ✅ time_slice(Query > 100 per 10) - invalid interval (no unit)
// * ✅ time_slice(Query > 100 per 10x) - invalid unit
// * ✅ time_slice(Query > abc per 10s) - non-numeric threshold
// * ✅ time_slice() - empty
// time_slice parses as regular word (see time_slice_parses_as_word_test):
// * ✅ TIME_SLICE(Query > 100 per 10s) - wrong case
// * ✅ timeslice(Query > 100 per 10s) - no underscore
// * ✅ time_slice Query > 100 per 10s - no parens
// time_slice parses but nested (see time_slice_nested_parsing_test):
// * ✅ time_slice(Query > 100 per 10s) + B - keyword as left operand
// * ✅ A + time_slice(Query > 100 per 10s) - keyword as right operand
// * ✅ (time_slice(Query > 100 per 10s)) - parenthesized keyword
// * ✅ time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s) - two keywords

pub fn parse_expr_test() {
  let lhs_complex =
    parens(OperatorExpr(
      parens(simple_op_cont("A", "B", Add)),
      prim_word("C"),
      Mul,
    ))
  let rhs_complex =
    parens(OperatorExpr(
      prim_word("D"),
      parens(simple_op_cont("E", "F", Add)),
      Sub,
    ))

  [
    // simple parenthesized word
    #("(A)", Ok(ExpContainer(parens(prim_word("A"))))),
    // double parenthesized word
    #("((A))", Ok(ExpContainer(parens(parens(prim_word("A")))))),
    // simple addition
    #("A + B", Ok(simple_exp_op_cont("A", "B", Add))),
    // simple subtraction
    #("A - B", Ok(simple_exp_op_cont("A", "B", Sub))),
    // simple multiplication
    #("A * B", Ok(simple_exp_op_cont("A", "B", Mul))),
    // simple division
    #("A / B", Ok(simple_exp_op_cont("A", "B", Div))),
    // order of precedence with parentheses
    #(
      "(A + B) / C",
      Ok(exp_op_cont(parens(simple_op_cont("A", "B", Add)), prim_word("C"), Div)),
    ),
    // complex nested parentheses
    #(
      "((A + B) * C) / (D - (E + F))",
      Ok(exp_op_cont(lhs_complex, rhs_complex, Div)),
    ),
    // mixed operators precedence
    #(
      "A * B + C / D - E",
      Ok(
        ExpContainer(OperatorExpr(
          simple_op_cont("A", "B", Mul),
          OperatorExpr(simple_op_cont("C", "D", Div), prim_word("E"), Sub),
          Add,
        )),
      ),
    ),
    // deeply nested expression
    #(
      "(A + (B * (C - D)))",
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
    ),
    // complex division expression
    #(
      "(X + Y * Z) / (A - B + C)",
      Ok(exp_op_cont(
        parens(OperatorExpr(prim_word("X"), simple_op_cont("Y", "Z", Mul), Add)),
        parens(OperatorExpr(simple_op_cont("A", "B", Sub), prim_word("C"), Add)),
        Div,
      )),
    ),
    // time_slice with basic expression
    #(
      "time_slice(Query > 1000000 per 10s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 1_000_000.0,
        interval_seconds: 10.0,
      )))),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    parse_expr(input) |> should.equal(expected)
  })
}

// ==== is_balanced_parens Tests ====
// * ✅ empty string
// * ✅ balanced parentheses
// * ✅ unbalanced parentheses
// * ✅ complex balanced parentheses

pub fn is_balanced_parens_test() {
  [
    // empty string
    #("", 0, 0, True),
    // balanced parentheses
    #("()", 0, 0, True),
    // unbalanced parentheses
    #("(()))", 0, 0, False),
    // complex balanced parentheses
    #("(a(b)(c)((())))", 11, 4, True),
  ]
  |> list.each(fn(tuple) {
    let #(input, pos, count, expected) = tuple
    is_balanced_parens(input, pos, count) |> should.equal(expected)
  })
}

// ==== find_rightmost_operator_at_level Tests ====
// * ✅ find rightmost division operator
// * ✅ find rightmost multiplication operator
// * ✅ find rightmost subtraction operator
// * ✅ error when operator not found at top level

pub fn find_rightmost_operator_at_level_test() {
  [
    // find rightmost division operator
    #("(A + B) / C", "/", Ok(#("(A + B)", "C"))),
    // find rightmost multiplication operator
    #("(A - B) / D * C", "*", Ok(#("(A - B) / D", "C"))),
    // find rightmost subtraction operator
    #("A - B / (D * C)", "-", Ok(#("A", "B / (D * C)"))),
  ]
  |> list.each(fn(tuple) {
    let #(input, operator, expected) = tuple
    find_rightmost_operator_at_level(input, operator, 0, 0, -1)
    |> should.equal(expected)
  })

  // error when operator not found at top level
  find_rightmost_operator_at_level("(A + B) / C", "+", 0, 0, -1)
  |> should.be_error
}

// ==== is_last_char Tests ====
// * ✅ empty string at index 0
// * ✅ single character at index 0
// * ✅ index not the last character
// * ✅ negative index
// * ✅ index beyond string length
// * ✅ index is the last character

pub fn is_last_char_test() {
  [
    // empty string at index 0
    #("", 0, True),
    // single character at index 0
    #("a", 0, True),
    // index not the last character
    #("()", 0, False),
    // negative index
    #("(()))", -1, False),
    // index beyond string length
    #("(()))", 100, False),
    // index is the last character
    #("(a(b)(c)((())))", 14, True),
  ]
  |> list.each(fn(tuple) {
    let #(input, index, expected) = tuple
    is_last_char(input, index) |> should.equal(expected)
  })
}

// ==== time_slice valid parsing Tests ====

pub fn time_slice_valid_parsing_test() {
  [
    // time_slice(Query > 1000000 per 10s) - basic with >
    #(
      "time_slice(Query > 1000000 per 10s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 1_000_000.0,
        interval_seconds: 10.0,
      )))),
    ),
    // time_slice(Query < 500 per 30s) - with <
    #(
      "time_slice(Query < 500 per 30s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: LessThan,
        threshold: 500.0,
        interval_seconds: 30.0,
      )))),
    ),
    // time_slice(Query >= 100 per 60s) - with >=
    #(
      "time_slice(Query >= 100 per 60s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThanOrEqualTo,
        threshold: 100.0,
        interval_seconds: 60.0,
      )))),
    ),
    // time_slice(Query <= 999 per 5s) - with <=
    #(
      "time_slice(Query <= 999 per 5s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: LessThanOrEqualTo,
        threshold: 999.0,
        interval_seconds: 5.0,
      )))),
    ),
    // time_slice(avg:system.cpu > 80 per 300s) - realistic metric query
    #(
      "time_slice(avg:system.cpu > 80 per 300s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "avg:system.cpu",
        comparator: GreaterThan,
        threshold: 80.0,
        interval_seconds: 300.0,
      )))),
    ),
    // time_slice( Query > 100 per 10s ) - whitespace handling
    #(
      "time_slice( Query > 100 per 10s )",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 100.0,
        interval_seconds: 10.0,
      )))),
    ),
    // time_slice(Query > 99.5 per 10s) - decimal threshold
    #(
      "time_slice(Query > 99.5 per 10s)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 99.5,
        interval_seconds: 10.0,
      )))),
    ),
    // time_slice(Query > 100 per 10m) - minutes interval
    #(
      "time_slice(Query > 100 per 10m)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 100.0,
        interval_seconds: 600.0,
      )))),
    ),
    // time_slice(Query > 100 per 1h) - hours interval
    #(
      "time_slice(Query > 100 per 1h)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 100.0,
        interval_seconds: 3600.0,
      )))),
    ),
    // time_slice(Query > 100 per 1.5h) - decimal interval
    #(
      "time_slice(Query > 100 per 1.5h)",
      Ok(ExpContainer(TimeSliceExpr(TimeSliceExp(
        query: "Query",
        comparator: GreaterThan,
        threshold: 100.0,
        interval_seconds: 5400.0,
      )))),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    parse_expr(input) |> should.equal(expected)
  })
}

// ==== time_slice invalid inner syntax Tests ====

pub fn time_slice_invalid_syntax_test() {
  [
    // time_slice(Query > 100) - missing per <interval>
    "time_slice(Query > 100)",
    // time_slice(Query 100 per 10s) - missing comparator
    "time_slice(Query 100 per 10s)",
    // time_slice(> 100 per 10s) - missing query
    "time_slice(> 100 per 10s)",
    // time_slice(Query > per 10s) - missing threshold
    "time_slice(Query > per 10s)",
    // time_slice(Query > 100 per) - missing interval
    "time_slice(Query > 100 per)",
    // time_slice(Query > 100 per s) - invalid interval (no number)
    "time_slice(Query > 100 per s)",
    // time_slice(Query > 100 per 10) - invalid interval (no unit)
    "time_slice(Query > 100 per 10)",
    // time_slice(Query > 100 per 10x) - invalid unit
    "time_slice(Query > 100 per 10x)",
    // time_slice(Query > abc per 10s) - non-numeric threshold
    "time_slice(Query > abc per 10s)",
    // time_slice() - empty
    "time_slice()",
  ]
  |> list.each(fn(input) { parse_expr(input) |> should.be_error })
}

// ==== time_slice parses as regular word Tests ====

pub fn time_slice_parses_as_word_test() {
  [
    // TIME_SLICE(Query > 100 per 10s) - wrong case
    #(
      "TIME_SLICE(Query > 100 per 10s)",
      Ok(ExpContainer(Primary(PrimaryWord(Word(
        "TIME_SLICE(Query > 100 per 10s)",
      ))))),
    ),
    // timeslice(Query > 100 per 10s) - no underscore
    #(
      "timeslice(Query > 100 per 10s)",
      Ok(ExpContainer(Primary(PrimaryWord(Word("timeslice(Query > 100 per 10s)"))))),
    ),
    // time_slice Query > 100 per 10s - no parens (parses as word)
    #(
      "time_slice Query > 100 per 10s",
      Ok(ExpContainer(Primary(PrimaryWord(Word(
        "time_slice Query > 100 per 10s",
      ))))),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    parse_expr(input) |> should.equal(expected)
  })
}

// ==== time_slice nested (parser succeeds, resolver rejects) Tests ====

pub fn time_slice_nested_parsing_test() {
  // These should parse successfully but the resolver will reject them
  // We just verify they parse without error here

  // time_slice(Query > 100 per 10s) + B - keyword as left operand
  let result1 = parse_expr("time_slice(Query > 100 per 10s) + B")
  should.be_ok(result1)

  // A + time_slice(Query > 100 per 10s) - keyword as right operand
  let result2 = parse_expr("A + time_slice(Query > 100 per 10s)")
  should.be_ok(result2)

  // (time_slice(Query > 100 per 10s)) - parenthesized keyword
  let result3 = parse_expr("(time_slice(Query > 100 per 10s))")
  should.be_ok(result3)

  // time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s) - two keywords
  let result4 = parse_expr("time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s)")
  should.be_ok(result4)
}
