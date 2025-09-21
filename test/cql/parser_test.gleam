import caffeine_lang/cql/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Primary, PrimaryExp, PrimaryWord,
  Sub, Word,
}

pub fn parse_expr_simple_parenthesized_word_test() {
  let input = "(A)"

  let expected_word = Word("A")
  let expected_primary = PrimaryWord(expected_word)
  let inner_expected_exp = Primary(expected_primary)
  let expected_exp = Ok(ExpContainer(Primary(PrimaryExp(inner_expected_exp))))

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}

pub fn parse_expr_simple_double_parenthesized_word_test() {
  let input = "((A))"

  let expected_word = Word("A")
  let expected_primary = PrimaryWord(expected_word)
  let inner_expected_exp = Primary(expected_primary)
  let second_innerexpected_exp = Primary(PrimaryExp(inner_expected_exp))
  let expected_exp =
    Ok(ExpContainer(Primary(PrimaryExp(second_innerexpected_exp))))

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}

pub fn parse_simple_addition_expr_test() {
  let input = "A + B"

  let expected_word_a = Word("A")
  let expected_word_b = Word("B")

  let expected_primary_a = Primary(PrimaryWord(expected_word_a))
  let expected_primary_b = Primary(PrimaryWord(expected_word_b))

  let expected_exp =
    Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Add)))

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}

pub fn parse_simple_subtraction_expr_test() {
  let input = "A - B"

  let expected_word_a = Word("A")
  let expected_word_b = Word("B")

  let expected_primary_a = Primary(PrimaryWord(expected_word_a))
  let expected_primary_b = Primary(PrimaryWord(expected_word_b))

  let expected_exp =
    Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Sub)))

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}

pub fn parse_simple_multiplication_expr_test() {
  let input = "A * B"

  let expected_word_a = Word("A")
  let expected_word_b = Word("B")

  let expected_primary_a = Primary(PrimaryWord(expected_word_a))
  let expected_primary_b = Primary(PrimaryWord(expected_word_b))

  let expected_exp =
    Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Mul)))

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}

pub fn parse_simple_division_expr_test() {
  let input = "A / B"

  let expected_word_a = Word("A")
  let expected_word_b = Word("B")

  let expected_primary_a = Primary(PrimaryWord(expected_word_a))
  let expected_primary_b = Primary(PrimaryWord(expected_word_b))

  let expected_exp =
    Ok(ExpContainer(OperatorExpr(expected_primary_a, expected_primary_b, Div)))

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}

pub fn parse_multiple_expr_for_order_of_precedence_test() {
  let input = "(A + B) / C"

  let expected_word_a = Word("A")
  let expected_word_b = Word("B")
  let expected_word_c = Word("C")

  let expected_primary_a = Primary(PrimaryWord(expected_word_a))
  let expected_primary_b = Primary(PrimaryWord(expected_word_b))
  let expected_primary_c = Primary(PrimaryWord(expected_word_c))

  let expected_exp =
    Ok(
      ExpContainer(OperatorExpr(
        Primary(
          PrimaryExp(OperatorExpr(expected_primary_a, expected_primary_b, Add)),
        ),
        expected_primary_c,
        Div,
      )),
    )

  let actual = parser.parse_expr(input)

  assert actual == expected_exp
}
