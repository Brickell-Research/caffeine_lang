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

// Test path with dots in field name (like http.url_details.path)
pub fn path_with_dots_in_field_test() {
  // Parse the actual string to see what the parser generates
  let query_str = "http.url_details.path:/v1/users/members"
  
  case parser.parse_expr(query_str) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      
      // Path with dots in field name should remain intact
      result
      |> should.equal("http.url_details.path:/v1/users/members")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

// Test path ending with closing brace (like in actual Datadog queries)
pub fn path_with_closing_brace_test() {
  // This simulates: {path:/v1/users/passwords/reset}
  let query_str = "path:/v1/users/passwords/reset}"
  
  case parser.parse_expr(query_str) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      
      // Path ending with } should remain intact
      result
      |> should.equal("path:/v1/users/passwords/reset}")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

// Test the exact pattern from the failing query
pub fn full_datadog_query_with_path_test() {
  // The CQL parser treats AND as a word, not an operator
  // So we need to test just the path portion that actually gets parsed
  let path_only = "http.url_details.path:/v1/users/passwords/reset"
  
  case parser.parse_expr(path_only) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      result |> should.equal("http.url_details.path:/v1/users/passwords/reset")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

// Test the actual Datadog query pattern with braces
pub fn datadog_query_in_braces_test() {
  // The actual query has the fields inside braces: {field1, field2, path:/v1/users}
  // After comma-to-AND conversion: {field1 AND field2 AND path:/v1/users}
  // The CQL parser will parse this as a single word token with divisions in the path
  let query_str = "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}"
  
  case parser.parse_expr(query_str) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      result |> should.equal("{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

// Test path with underscores in the last segment
pub fn path_with_underscore_segment_test() {
  let query_str = "http.url_details.path:/oauth/access_token"
  
  case parser.parse_expr(query_str) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      result |> should.equal("http.url_details.path:/oauth/access_token")
    }
    Error(_) -> {
      should.fail()
    }
  }
}
