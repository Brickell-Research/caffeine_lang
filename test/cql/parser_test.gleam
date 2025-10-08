import caffeine_lang/cql/parser.{
  Add, Div, ExpContainer, Mul, OperatorExpr, Sub, is_balanced_parens,
}
import cql/test_helpers.{
  exp_op_cont, parens, prim_word, simple_exp_op_cont, simple_op_cont,
}
import gleeunit/should

pub fn parse_expr_parses_test() {
  // simple parenthesized word test
  parser.parse_expr("(A)")
  |> should.equal(Ok(ExpContainer(parens(prim_word("A")))))

  // double parenthesized word test
  parser.parse_expr("((A))")
  |> should.equal(Ok(ExpContainer(parens(parens(prim_word("A"))))))

  // simple addition expression tests
  parser.parse_expr("A + B")
  |> should.equal(Ok(simple_exp_op_cont("A", "B", Add)))

  // simple subtraction expression test
  parser.parse_expr("A - B")
  |> should.equal(Ok(simple_exp_op_cont("A", "B", Sub)))

  // simple multiplication expression test
  parser.parse_expr("A * B")
  |> should.equal(Ok(simple_exp_op_cont("A", "B", Mul)))

  // simple division expression tests
  parser.parse_expr("A / B")
  |> should.equal(Ok(simple_exp_op_cont("A", "B", Div)))

  // expression with order of precedence using parentheses test
  parser.parse_expr("(A + B) / C")
  |> should.equal(
    Ok(exp_op_cont(parens(simple_op_cont("A", "B", Add)), prim_word("C"), Div)),
  )

  // complex nested parentheses test
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
  parser.parse_expr("((A + B) * C) / (D - (E + F))")
  |> should.equal(Ok(exp_op_cont(lhs, rhs, Div)))

  // mixed operatators precedence test
  parser.parse_expr("A * B + C / D - E")
  |> should.equal(
    Ok(
      ExpContainer(OperatorExpr(
        simple_op_cont("A", "B", Mul),
        OperatorExpr(simple_op_cont("C", "D", Div), prim_word("E"), Sub),
        Add,
      )),
    ),
  )

  // deeply nested expression test
  parser.parse_expr("(A + (B * (C - D)))")
  |> should.equal(
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
  )

  // complex division expression test
  parser.parse_expr("(X + Y * Z) / (A - B + C)")
  |> should.equal(
    Ok(exp_op_cont(
      parens(OperatorExpr(prim_word("X"), simple_op_cont("Y", "Z", Mul), Add)),
      parens(OperatorExpr(simple_op_cont("A", "B", Sub), prim_word("C"), Add)),
      Div,
    )),
  )
}

pub fn is_balanced_parens_test() {
  is_balanced_parens("", 0, 0)
  |> should.be_true

  is_balanced_parens("()", 0, 0)
  |> should.be_true

  is_balanced_parens("(()))", 0, 0)
  |> should.be_false

  is_balanced_parens("(()))", 0, 0)
  |> should.be_false

  is_balanced_parens("(a(b)(c)((())))", 11, 4)
  |> should.be_true
}
