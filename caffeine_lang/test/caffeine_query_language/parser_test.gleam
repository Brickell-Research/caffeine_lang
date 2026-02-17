import caffeine_lang/errors
import caffeine_query_language/ast.{
  Add, Div, GreaterThan, GreaterThanOrEqualTo, LessThan, LessThanOrEqualTo, Mul,
  OperatorExpr, Primary, PrimaryWord, Sub, TimeSliceExp, TimeSliceExpr, Word,
}
import caffeine_query_language/parser.{
  find_rightmost_operator_at_level, is_balanced_parens, is_last_char, parse_expr,
}
import caffeine_query_language/test_helpers as cql_test_helpers
import gleeunit/should
import test_helpers

const exp_op = cql_test_helpers.exp_op

const parens = cql_test_helpers.parens

const prim_word = cql_test_helpers.prim_word

const simple_exp_op = cql_test_helpers.simple_exp_op

const simple_op_cont = cql_test_helpers.simple_op_cont

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
    #("simple parenthesized word", "(A)", Ok(parens(prim_word("A")))),
    // double parenthesized word
    #("double parenthesized word", "((A))", Ok(parens(parens(prim_word("A"))))),
    // simple addition
    #("simple addition", "A + B", Ok(simple_exp_op("A", "B", Add))),
    // simple subtraction
    #("simple subtraction", "A - B", Ok(simple_exp_op("A", "B", Sub))),
    // simple multiplication
    #("simple multiplication", "A * B", Ok(simple_exp_op("A", "B", Mul))),
    // simple division
    #("simple division", "A / B", Ok(simple_exp_op("A", "B", Div))),
    // order of precedence with parentheses
    #(
      "order of precedence with parentheses",
      "(A + B) / C",
      Ok(exp_op(parens(simple_op_cont("A", "B", Add)), prim_word("C"), Div)),
    ),
    // complex nested parentheses
    #(
      "complex nested parentheses",
      "((A + B) * C) / (D - (E + F))",
      Ok(exp_op(lhs_complex, rhs_complex, Div)),
    ),
    // mixed operators precedence
    #(
      "mixed operators precedence",
      "A * B + C / D - E",
      Ok(OperatorExpr(
        simple_op_cont("A", "B", Mul),
        OperatorExpr(simple_op_cont("C", "D", Div), prim_word("E"), Sub),
        Add,
      )),
    ),
    // deeply nested expression
    #(
      "deeply nested expression",
      "(A + (B * (C - D)))",
      Ok(
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
    // complex division expression
    #(
      "complex division expression",
      "(X + Y * Z) / (A - B + C)",
      Ok(exp_op(
        parens(OperatorExpr(prim_word("X"), simple_op_cont("Y", "Z", Mul), Add)),
        parens(OperatorExpr(simple_op_cont("A", "B", Sub), prim_word("C"), Add)),
        Div,
      )),
    ),
    // time_slice with basic expression
    #(
      "time_slice with basic expression",
      "time_slice(Query > 1000000 per 10s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 1_000_000.0,
          interval_seconds: 10.0,
        )),
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_expr)
}

// ==== Operator precedence Tests ====
// * ✅ multiply binds tighter than add: a + b * c
// * ✅ multiply binds tighter than add: a * b + c
// * ✅ division left-associative: a / b / c
// * ✅ subtraction left-associative: a - b - c
// * ✅ mixed add/sub with multiply: a + b * c - d
pub fn operator_precedence_test() {
  [
    // a + b * c → Add(a, Mul(b, c)) — multiply binds tighter
    #(
      "multiply binds tighter than add: a + b * c",
      "a + b * c",
      Ok(OperatorExpr(prim_word("a"), simple_op_cont("b", "c", Mul), Add)),
    ),
    // a * b + c → Add(Mul(a, b), c) — multiply binds tighter
    #(
      "multiply binds tighter than add: a * b + c",
      "a * b + c",
      Ok(OperatorExpr(simple_op_cont("a", "b", Mul), prim_word("c"), Add)),
    ),
    // a / b / c — the parser finds the rightmost "/" at paren-level 0,
    // splitting into "a / b" and "c", then recursively parses "a / b".
    #(
      "division left-associative: a / b / c",
      "a / b / c",
      Ok(OperatorExpr(simple_op_cont("a", "b", Div), prim_word("c"), Div)),
    ),
    // a - b - c — same strategy: rightmost "-" splits into "a - b" and "c"
    #(
      "subtraction left-associative: a - b - c",
      "a - b - c",
      Ok(OperatorExpr(simple_op_cont("a", "b", Sub), prim_word("c"), Sub)),
    ),
    // a + b * c - d → Add(a, Sub(Mul(b, c), d))
    #(
      "mixed add/sub with multiply: a + b * c - d",
      "a + b * c - d",
      Ok(OperatorExpr(
        prim_word("a"),
        OperatorExpr(simple_op_cont("b", "c", Mul), prim_word("d"), Sub),
        Add,
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_expr)
}

// ==== is_balanced_parens Tests ====
// * ✅ empty string
// * ✅ balanced parentheses
// * ✅ unbalanced parentheses
// * ✅ complex balanced parentheses

pub fn is_balanced_parens_test() {
  [
    // empty string
    #("empty string", "", 0, 0, True),
    // balanced parentheses
    #("balanced parentheses", "()", 0, 0, True),
    // unbalanced parentheses
    #("unbalanced parentheses", "(()))", 0, 0, False),
    // complex balanced parentheses
    #("complex balanced parentheses", "(a(b)(c)((())))", 11, 4, True),
  ]
  |> test_helpers.array_based_test_executor_3(is_balanced_parens)
}

// ==== find_rightmost_operator_at_level Tests ====
// * ✅ find rightmost division operator
// * ✅ find rightmost multiplication operator
// * ✅ find rightmost subtraction operator
// * ✅ error when operator not found at top level

pub fn find_rightmost_operator_at_level_test() {
  [
    // find rightmost division operator
    #(
      "find rightmost division operator",
      "(A + B) / C",
      "/",
      Ok(#("(A + B)", "C")),
    ),
    // find rightmost multiplication operator
    #(
      "find rightmost multiplication operator",
      "(A - B) / D * C",
      "*",
      Ok(#("(A - B) / D", "C")),
    ),
    // find rightmost subtraction operator
    #(
      "find rightmost subtraction operator",
      "A - B / (D * C)",
      "-",
      Ok(#("A", "B / (D * C)")),
    ),
    // error when operator not found at top level
    #(
      "error when operator not found at top level",
      "(A + B) / C",
      "+",
      Error(errors.CQLParserError(
        msg: "Operator not found",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(input, operator) {
    find_rightmost_operator_at_level(input, operator, 0, 0, -1)
  })
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
    #("empty string at index 0", "", 0, True),
    // single character at index 0
    #("single character at index 0", "a", 0, True),
    // index not the last character
    #("index not the last character", "()", 0, False),
    // negative index
    #("negative index", "(()))", -1, False),
    // index beyond string length
    #("index beyond string length", "(()))", 100, False),
    // index is the last character
    #("index is the last character", "(a(b)(c)((())))", 14, True),
  ]
  |> test_helpers.array_based_test_executor_2(is_last_char)
}

// ==== time_slice valid parsing Tests ====
pub fn time_slice_valid_parsing_test() {
  [
    // time_slice(Query > 1000000 per 10s) - basic with >
    #(
      "basic with >",
      "time_slice(Query > 1000000 per 10s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 1_000_000.0,
          interval_seconds: 10.0,
        )),
      ),
    ),
    // time_slice(Query < 500 per 30s) - with <
    #(
      "with <",
      "time_slice(Query < 500 per 30s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: LessThan,
          threshold: 500.0,
          interval_seconds: 30.0,
        )),
      ),
    ),
    // time_slice(Query >= 100 per 60s) - with >=
    #(
      "with >=",
      "time_slice(Query >= 100 per 60s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThanOrEqualTo,
          threshold: 100.0,
          interval_seconds: 60.0,
        )),
      ),
    ),
    // time_slice(Query <= 999 per 5s) - with <=
    #(
      "with <=",
      "time_slice(Query <= 999 per 5s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: LessThanOrEqualTo,
          threshold: 999.0,
          interval_seconds: 5.0,
        )),
      ),
    ),
    // time_slice(avg:system.cpu > 80 per 300s) - realistic metric query
    #(
      "realistic metric query",
      "time_slice(avg:system.cpu > 80 per 300s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "avg:system.cpu",
          comparator: GreaterThan,
          threshold: 80.0,
          interval_seconds: 300.0,
        )),
      ),
    ),
    // time_slice( Query > 100 per 10s ) - whitespace handling
    #(
      "whitespace handling",
      "time_slice( Query > 100 per 10s )",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 100.0,
          interval_seconds: 10.0,
        )),
      ),
    ),
    // time_slice(Query > 99.5 per 10s) - decimal threshold
    #(
      "decimal threshold",
      "time_slice(Query > 99.5 per 10s)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 99.5,
          interval_seconds: 10.0,
        )),
      ),
    ),
    // time_slice(Query > 100 per 10m) - minutes interval
    #(
      "minutes interval",
      "time_slice(Query > 100 per 10m)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 100.0,
          interval_seconds: 600.0,
        )),
      ),
    ),
    // time_slice(Query > 100 per 1h) - hours interval
    #(
      "hours interval",
      "time_slice(Query > 100 per 1h)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 100.0,
          interval_seconds: 3600.0,
        )),
      ),
    ),
    // time_slice(Query > 100 per 1.5h) - decimal interval
    #(
      "decimal interval",
      "time_slice(Query > 100 per 1.5h)",
      Ok(
        TimeSliceExpr(TimeSliceExp(
          query: "Query",
          comparator: GreaterThan,
          threshold: 100.0,
          interval_seconds: 5400.0,
        )),
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_expr)
}

// ==== time_slice invalid inner syntax Tests ====

pub fn time_slice_invalid_syntax_test() {
  [
    // time_slice(Query > 100) - missing per <interval>
    #(
      "missing per interval",
      "time_slice(Query > 100)",
      Error("Missing 'per' keyword in time_slice expression"),
    ),
    // time_slice(Query 100 per 10s) - missing comparator
    #(
      "missing comparator",
      "time_slice(Query 100 per 10s)",
      Error("No comparator found in time_slice expression"),
    ),
    // time_slice(> 100 per 10s) - missing query
    #(
      "missing query",
      "time_slice(> 100 per 10s)",
      Error("Missing query in time_slice expression"),
    ),
    // time_slice(Query > per 10s) - missing threshold
    #(
      "missing threshold",
      "time_slice(Query > per 10s)",
      Error("Missing threshold in time_slice expression"),
    ),
    // time_slice(Query > 100 per) - missing interval
    #(
      "missing interval",
      "time_slice(Query > 100 per)",
      Error("Missing interval in time_slice expression"),
    ),
    // time_slice(Query > 100 per s) - invalid interval (no number)
    #(
      "invalid interval (no number)",
      "time_slice(Query > 100 per s)",
      Error("Invalid interval number ''"),
    ),
    // time_slice(Query > 100 per 10) - invalid interval (no unit)
    #(
      "invalid interval (no unit)",
      "time_slice(Query > 100 per 10)",
      Error("Invalid interval unit '0' (expected s, m, or h)"),
    ),
    // time_slice(Query > 100 per 10x) - invalid unit
    #(
      "invalid unit",
      "time_slice(Query > 100 per 10x)",
      Error("Invalid interval unit 'x' (expected s, m, or h)"),
    ),
    // time_slice(Query > abc per 10s) - non-numeric threshold
    #(
      "non-numeric threshold",
      "time_slice(Query > abc per 10s)",
      Error("Invalid threshold 'abc' in time_slice expression"),
    ),
    // time_slice() - empty
    #("empty time_slice", "time_slice()", Error("Empty time_slice expression")),
  ]
  |> test_helpers.array_based_test_executor_1(parse_expr)
}

// ==== time_slice parses as regular word Tests ====

pub fn time_slice_parses_as_word_test() {
  [
    // TIME_SLICE(Query > 100 per 10s) - wrong case
    #(
      "wrong case",
      "TIME_SLICE(Query > 100 per 10s)",
      Ok(Primary(PrimaryWord(Word("TIME_SLICE(Query > 100 per 10s)")))),
    ),
    // timeslice(Query > 100 per 10s) - no underscore
    #(
      "no underscore",
      "timeslice(Query > 100 per 10s)",
      Ok(Primary(PrimaryWord(Word("timeslice(Query > 100 per 10s)")))),
    ),
    // time_slice Query > 100 per 10s - no parens (parses as word)
    #(
      "no parens",
      "time_slice Query > 100 per 10s",
      Ok(Primary(PrimaryWord(Word("time_slice Query > 100 per 10s")))),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_expr)
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
  let result4 =
    parse_expr("time_slice(A > 1 per 1s) / time_slice(B > 2 per 2s)")
  should.be_ok(result4)
}
