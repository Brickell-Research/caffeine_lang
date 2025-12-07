import caffeine_query_language/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Sub,
  find_rightmost_operator_at_level, is_balanced_parens, parse_expr,
}
import caffeine_query_language/test_helpers.{
  assert_last_char, exp_op_cont, parens, prim_word, simple_exp_op_cont,
  simple_op_cont,
}
import gleeunit/should

// ==================== parse_expr tests ====================
pub fn parse_expr_should_parse_a_simple_parenthesized_word_test() {
  let expected = Ok(ExpContainer(parens(prim_word("A"))))

  let actual = parse_expr("(A)")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_double_parenthesized_word_test() {
  let expected = Ok(ExpContainer(parens(parens(prim_word("A")))))

  let actual = parse_expr("((A))")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_simple_addition_expression_test() {
  let expected = Ok(simple_exp_op_cont("A", "B", Add))

  let actual = parse_expr("A + B")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_simple_subtraction_expression_test() {
  let expected = Ok(simple_exp_op_cont("A", "B", Sub))

  let actual = parse_expr("A - B")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_simple_multiplication_expression_test() {
  let expected = Ok(simple_exp_op_cont("A", "B", Mul))

  let actual = parse_expr("A * B")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_simple_division_expression_test() {
  let expected = Ok(simple_exp_op_cont("A", "B", Div))

  let actual = parse_expr("A / B")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_an_expression_with_order_of_precedence_using_parentheses_test() {
  let expected =
    Ok(exp_op_cont(parens(simple_op_cont("A", "B", Add)), prim_word("C"), Div))

  let actual = parse_expr("(A + B) / C")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_complex_nested_parentheses_expression_test() {
  let lhs =
    parens(OperatorExpr(
      parens(simple_op_cont("A", "B", Add)),
      prim_word("C"),
      Mul,
    ))

  let rhs =
    parens(OperatorExpr(
      prim_word("D"),
      parens(simple_op_cont("E", "F", Add)),
      Sub,
    ))
  let expected = Ok(exp_op_cont(lhs, rhs, Div))

  let actual = parse_expr("((A + B) * C) / (D - (E + F))")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_an_expression_with_mixed_operators_precedence_test() {
  let expected =
    Ok(
      ExpContainer(OperatorExpr(
        simple_op_cont("A", "B", Mul),
        OperatorExpr(simple_op_cont("C", "D", Div), prim_word("E"), Sub),
        Add,
      )),
    )

  let actual = parse_expr("A * B + C / D - E")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_deeply_nested_expression_test() {
  let expected =
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
    )

  let actual = parse_expr("(A + (B * (C - D)))")

  actual |> should.equal(expected)
}

pub fn parse_expr_should_parse_a_complex_division_expression_test() {
  let expected =
    Ok(exp_op_cont(
      parens(OperatorExpr(prim_word("X"), simple_op_cont("Y", "Z", Mul), Add)),
      parens(OperatorExpr(simple_op_cont("A", "B", Sub), prim_word("C"), Add)),
      Div,
    ))
  let actual = parse_expr("(X + Y * Z) / (A - B + C)")

  actual |> should.equal(expected)
}

// ==================== is_balanced_parens tests ====================
pub fn is_balanced_parens_should_return_true_for_an_empty_string_test() {
  is_balanced_parens("", 0, 0)
  |> should.be_true
}

pub fn is_balanced_parens_should_return_true_for_balanced_parentheses_test() {
  is_balanced_parens("()", 0, 0)
  |> should.be_true
}

pub fn is_balanced_parens_should_return_false_for_unbalanced_parentheses_test() {
  is_balanced_parens("(()))", 0, 0)
  |> should.be_false
}

pub fn is_balanced_parens_should_return_true_for_complex_balanced_parentheses_test() {
  is_balanced_parens("(a(b)(c)((())))", 11, 4)
  |> should.be_true
}

// ==================== find_rightmost_operator_at_level tests ====================
pub fn find_rightmost_operator_at_level_should_find_the_rightmost_division_operator_test() {
  let actual = find_rightmost_operator_at_level("(A + B) / C", "/", 0, 0, -1)
  let expected = Ok(#("(A + B)", "C"))
  actual |> should.equal(expected)
}

pub fn find_rightmost_operator_at_level_should_find_the_rightmost_multiplication_operator_test() {
  let actual =
    find_rightmost_operator_at_level("(A - B) / D * C", "*", 0, 0, -1)
  let expected = Ok(#("(A - B) / D", "C"))
  actual |> should.equal(expected)
}

pub fn find_rightmost_operator_at_level_should_find_the_rightmost_subtraction_operator_test() {
  let actual =
    find_rightmost_operator_at_level("A - B / (D * C)", "-", 0, 0, -1)
  let expected = Ok(#("A", "B / (D * C)"))
  actual |> should.equal(expected)
}

pub fn find_rightmost_operator_at_level_should_return_an_error_when_operator_is_not_found_at_the_top_level_test() {
  let actual = find_rightmost_operator_at_level("(A + B) / C", "+", 0, 0, -1)
  actual |> should.be_error
}

// ==================== is_last_char tests ====================
pub fn is_last_char_should_return_true_for_empty_string_at_index_0_test() {
  assert_last_char("", 0, True)
}

pub fn is_last_char_should_return_true_for_single_character_string_at_index_0_test() {
  assert_last_char("a", 0, True)
}

pub fn is_last_char_should_return_false_when_index_is_not_the_last_character_test() {
  assert_last_char("()", 0, False)
}

pub fn is_last_char_should_return_false_for_negative_index_test() {
  assert_last_char("(()))", -1, False)
}

pub fn is_last_char_should_return_false_for_index_beyond_string_length_test() {
  assert_last_char("(()))", 100, False)
}

pub fn is_last_char_should_return_true_when_index_is_the_last_character_test() {
  assert_last_char("(a(b)(c)((())))", 14, True)
}
