import caffeine_query_language/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Sub,
  find_rightmost_operator_at_level, is_balanced_parens, is_last_char, parse_expr,
}
import caffeine_query_language/test_helpers.{
  exp_op_cont, parens, prim_word, simple_exp_op_cont, simple_op_cont,
}
import gleam/list
import gleeunit/should

// ==== parse_expr Tests ====
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
    #("((A + B) * C) / (D - (E + F))", Ok(exp_op_cont(lhs_complex, rhs_complex, Div))),
    // mixed operators precedence
    #(
      "A * B + C / D - E",
      Ok(ExpContainer(OperatorExpr(
        simple_op_cont("A", "B", Mul),
        OperatorExpr(simple_op_cont("C", "D", Div), prim_word("E"), Sub),
        Add,
      ))),
    ),
    // deeply nested expression
    #(
      "(A + (B * (C - D)))",
      Ok(ExpContainer(parens(OperatorExpr(
        prim_word("A"),
        parens(OperatorExpr(
          prim_word("B"),
          parens(simple_op_cont("C", "D", Sub)),
          Mul,
        )),
        Add,
      )))),
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
