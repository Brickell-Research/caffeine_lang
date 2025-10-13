import caffeine_lang/cql/generator
import caffeine_lang/cql/parser
import caffeine_lang/cql/resolver
import gleeunit/should

pub fn generate_datadog_query_test() {
  // Good over bad expression
  let assert Ok(parsed) = parser.parse_expr("A + B / C")
  let assert Ok(resolved) = resolver.resolve_primitives(parsed)

  generator.generate_datadog_query(resolved)
  |> should.equal(
    "query {
    numerator = \"A + B\"
    denominator = \"C\"
  }
",
  )

  // Nested and complex good over bad expression
  let assert Ok(parsed) = parser.parse_expr("(A - G) + B / (C + (D + E) * F)")
  let assert Ok(resolved) = resolver.resolve_primitives(parsed)

  generator.generate_datadog_query(resolved)
  |> should.equal(
    "query {
    numerator = \"A - G + B\"
    denominator = \"C + (D + E) * F\"
  }
",
  )
}

// Test that URL paths with slashes don't get spaces added
pub fn path_without_spaces_test() {
  // Create expression: metric{path:/v1/users}
  // This will be parsed as: metric{path: / v1 / users} (division operators)
  // But the generator should detect it's a path and not add spaces
  let path_part = parser.OperatorExpr(
    parser.Primary(parser.PrimaryWord(parser.Word("metric{path:"))),
    parser.OperatorExpr(
      parser.Primary(parser.PrimaryWord(parser.Word("v1"))),
      parser.Primary(parser.PrimaryWord(parser.Word("users}"))),
      parser.Div,
    ),
    parser.Div,
  )
  
  let result = generator.exp_to_string(path_part)
  
  // The path should remain intact without spaces around slashes
  result
  |> should.equal("metric{path:/v1/users}")
}

// Test that normal division operations still get spaces
pub fn division_with_spaces_test() {
  // Create expression: metric_a / metric_b (actual mathematical division)
  let div_expr = parser.OperatorExpr(
    parser.Primary(parser.PrimaryWord(parser.Word("metric_a"))),
    parser.Primary(parser.PrimaryWord(parser.Word("metric_b"))),
    parser.Div,
  )
  
  let result = generator.exp_to_string(div_expr)
  
  // Mathematical division should have spaces
  result
  |> should.equal("metric_a / metric_b")
}

// Test path with multiple segments
pub fn complex_path_test() {
  // Create expression: path:/v1/users/passwords/reset
  let path_expr = parser.OperatorExpr(
    parser.Primary(parser.PrimaryWord(parser.Word("path:"))),
    parser.OperatorExpr(
      parser.OperatorExpr(
        parser.OperatorExpr(
          parser.Primary(parser.PrimaryWord(parser.Word("v1"))),
          parser.Primary(parser.PrimaryWord(parser.Word("users"))),
          parser.Div,
        ),
        parser.Primary(parser.PrimaryWord(parser.Word("passwords"))),
        parser.Div,
      ),
      parser.Primary(parser.PrimaryWord(parser.Word("reset"))),
      parser.Div,
    ),
    parser.Div,
  )
  
  let result = generator.exp_to_string(path_expr)
  
  // Complex path should remain intact
  result
  |> should.equal("path:/v1/users/passwords/reset")
}

// Test path with wildcard
pub fn path_with_wildcard_test() {
  // Create expression: path:/v1/users/forgot*
  let path_expr = parser.OperatorExpr(
    parser.Primary(parser.PrimaryWord(parser.Word("path:"))),
    parser.OperatorExpr(
      parser.OperatorExpr(
        parser.Primary(parser.PrimaryWord(parser.Word("v1"))),
        parser.Primary(parser.PrimaryWord(parser.Word("users"))),
        parser.Div,
      ),
      parser.Primary(parser.PrimaryWord(parser.Word("forgot*"))),
      parser.Div,
    ),
    parser.Div,
  )
  
  let result = generator.exp_to_string(path_expr)
  
  // Path with wildcard should remain intact
  result
  |> should.equal("path:/v1/users/forgot*")
}

// Test that division with query braces gets spaces (not a path)
pub fn division_with_braces_test() {
  // Create expression: metric{a:b} / metric{c:d}
  let div_expr = parser.OperatorExpr(
    parser.Primary(parser.PrimaryWord(parser.Word("metric{a:b}"))),
    parser.Primary(parser.PrimaryWord(parser.Word("metric{c:d}"))),
    parser.Div,
  )
  
  let result = generator.exp_to_string(div_expr)
  
  // Division with braces should have spaces (not a path)
  result
  |> should.equal("metric{a:b} / metric{c:d}")
}
