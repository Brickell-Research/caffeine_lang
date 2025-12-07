import caffeine_query_language/generator
import caffeine_query_language/parser
import caffeine_query_language/resolver
import gleeunit/should

pub fn generate_datadog_query_should_generate_a_query_for_a_good_over_bad_expression_test() {
  let assert Ok(parsed) = parser.parse_expr("(A + B) / C")
  let assert Ok(resolved) = resolver.resolve_primitives(parsed)

  generator.generate_datadog_query(resolved)
  |> should.equal(
    "query {
    numerator = \"A + B\"
    denominator = \"C\"
  }
",
  )
}

pub fn generate_datadog_query_should_generate_a_query_for_a_nested_and_complex_good_over_bad_expression_test() {
  let assert Ok(parsed) = parser.parse_expr("((A - G) + B) / (C + (D + E) * F)")
  let assert Ok(resolved) = resolver.resolve_primitives(parsed)

  generator.generate_datadog_query(resolved)
  |> should.equal(
    "query {
    numerator = \"(A - G) + B\"
    denominator = \"C + (D + E) * F\"
  }
",
  )
}

pub fn exp_to_string_should_not_add_spaces_to_url_paths_with_slashes_test() {
  // Create expression: metric{path:/v1/users}
  // This will be parsed as: metric{path: / v1 / users} (division operators)
  // But the generator should detect it's a path and not add spaces
  let path_part =
    parser.OperatorExpr(
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

pub fn exp_to_string_should_handle_paths_with_multiple_segments_test() {
  // Create expression: path:/v1/users/passwords/reset
  let path_expr =
    parser.OperatorExpr(
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

pub fn exp_to_string_should_handle_paths_with_wildcards_test() {
  // Create expression: path:/v1/users/forgot*
  let path_expr =
    parser.OperatorExpr(
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

pub fn exp_to_string_should_handle_paths_with_dots_in_field_name_test() {
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

pub fn exp_to_string_should_handle_paths_ending_with_closing_brace_test() {
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

pub fn exp_to_string_should_handle_full_datadog_query_path_pattern_test() {
  // The CQL parser treats AND as a word, not an operator
  // So we need to test just the path portion that actually gets parsed
  let path_only = "http.url_details.path:/v1/users/passwords/reset"

  case parser.parse_expr(path_only) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      result
      |> should.equal("http.url_details.path:/v1/users/passwords/reset")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn exp_to_string_should_handle_datadog_query_pattern_with_braces_test() {
  // The actual query has the fields inside braces: {field1, field2, path:/v1/users}
  // After comma-to-AND conversion: {field1 AND field2 AND path:/v1/users}
  // The CQL parser will parse this as a single word token with divisions in the path
  let query_str =
    "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}"

  case parser.parse_expr(query_str) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      result
      |> should.equal(
        "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}",
      )
    }
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn exp_to_string_should_handle_paths_with_underscores_in_the_last_segment_test() {
  let query_str = "http.url_details.path:/oauth/access_token"

  case parser.parse_expr(query_str) {
    Ok(parser.ExpContainer(exp)) -> {
      let result = generator.exp_to_string(exp)
      result
      |> should.equal("http.url_details.path:/oauth/access_token")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn exp_to_string_should_add_spaces_to_normal_division_operations_test() {
  // Create expression: metric_a / metric_b (actual mathematical division)
  let div_expr =
    parser.OperatorExpr(
      parser.Primary(parser.PrimaryWord(parser.Word("metric_a"))),
      parser.Primary(parser.PrimaryWord(parser.Word("metric_b"))),
      parser.Div,
    )

  let result = generator.exp_to_string(div_expr)

  // Mathematical division should have spaces
  result
  |> should.equal("metric_a / metric_b")
}

pub fn exp_to_string_should_add_spaces_to_division_with_query_braces_test() {
  // Create expression: metric{a:b} / metric{c:d}
  let div_expr =
    parser.OperatorExpr(
      parser.Primary(parser.PrimaryWord(parser.Word("metric{a:b}"))),
      parser.Primary(parser.PrimaryWord(parser.Word("metric{c:d}"))),
      parser.Div,
    )

  let result = generator.exp_to_string(div_expr)

  // Division with braces should have spaces (not a path)
  result
  |> should.equal("metric{a:b} / metric{c:d}")
}
