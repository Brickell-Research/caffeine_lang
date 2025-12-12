import caffeine_query_language/generator
import caffeine_query_language/parser
import gleam/dict
import gleam/list
import gleeunit/should
import terra_madre/hcl

// ==== resolve_slo_to_hcl Tests ====
// good_over_total
// * ✅ simple good over total query returns MetricSlo with query block
// * ✅ nested expression returns correct numerator/denominator
// time_slice
// * ✅ time_slice returns TimeSliceSlo with sli_specification block

pub fn resolve_slo_to_hcl_good_over_total_test() {
  // simple good over total query
  let result =
    generator.resolve_slo_to_hcl(
      "numerator / denominator",
      dict.from_list([
        #("numerator", "sum:http.requests{status:2xx}"),
        #("denominator", "sum:http.requests{*}"),
      ]),
    )

  let assert Ok(generator.ResolvedSloHcl(slo_type, blocks)) = result
  should.equal(slo_type, generator.MetricSlo)
  should.equal(list.length(blocks), 1)

  let assert [query_block] = blocks
  should.equal(query_block.type_, "query")
  should.equal(
    dict.get(query_block.attributes, "numerator"),
    Ok(hcl.StringLiteral("sum:http.requests{status:2xx}")),
  )
  should.equal(
    dict.get(query_block.attributes, "denominator"),
    Ok(hcl.StringLiteral("sum:http.requests{*}")),
  )
}

pub fn resolve_slo_to_hcl_time_slice_test() {
  // time_slice returns TimeSliceSlo with sli_specification block
  let result =
    generator.resolve_slo_to_hcl(
      "time_slice(avg:system.cpu{env:production} > 99.5 per 300s)",
      dict.new(),
    )

  let assert Ok(generator.ResolvedSloHcl(slo_type, blocks)) = result
  should.equal(slo_type, generator.TimeSliceSlo)
  should.equal(list.length(blocks), 1)

  let assert [sli_spec_block] = blocks
  should.equal(sli_spec_block.type_, "sli_specification")

  // Check nested time_slice block exists
  should.equal(list.length(sli_spec_block.blocks), 1)
  let assert [time_slice_block] = sli_spec_block.blocks
  should.equal(time_slice_block.type_, "time_slice")
  should.equal(
    dict.get(time_slice_block.attributes, "comparator"),
    Ok(hcl.StringLiteral(">")),
  )
  should.equal(
    dict.get(time_slice_block.attributes, "query_interval_seconds"),
    Ok(hcl.IntLiteral(300)),
  )
  should.equal(
    dict.get(time_slice_block.attributes, "threshold"),
    Ok(hcl.FloatLiteral(99.5)),
  )
}

// ==== exp_to_string Tests ====
// * ✅ path with slashes (no spaces)
// * ✅ path with multiple segments
// * ✅ path with wildcards
// * ✅ path with dots in field name
// * ✅ path ending with closing brace
// * ✅ full datadog query path pattern
// * ✅ datadog query pattern with braces
// * ✅ path with underscores in last segment
// * ✅ normal division (with spaces)
// * ✅ division with query braces (with spaces)

pub fn exp_to_string_path_expressions_test() {
  // Tests that use manually constructed ASTs for path expressions
  [
    // path with slashes (no spaces) - metric{path:/v1/users}
    #(
      parser.OperatorExpr(
        parser.Primary(parser.PrimaryWord(parser.Word("metric{path:"))),
        parser.OperatorExpr(
          parser.Primary(parser.PrimaryWord(parser.Word("v1"))),
          parser.Primary(parser.PrimaryWord(parser.Word("users}"))),
          parser.Div,
        ),
        parser.Div,
      ),
      "metric{path:/v1/users}",
    ),
    // path with multiple segments - path:/v1/users/passwords/reset
    #(
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
      ),
      "path:/v1/users/passwords/reset",
    ),
    // path with wildcards - path:/v1/users/forgot*
    #(
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
      ),
      "path:/v1/users/forgot*",
    ),
    // normal division (with spaces)
    #(
      parser.OperatorExpr(
        parser.Primary(parser.PrimaryWord(parser.Word("metric_a"))),
        parser.Primary(parser.PrimaryWord(parser.Word("metric_b"))),
        parser.Div,
      ),
      "metric_a / metric_b",
    ),
    // division with query braces (with spaces)
    #(
      parser.OperatorExpr(
        parser.Primary(parser.PrimaryWord(parser.Word("metric{a:b}"))),
        parser.Primary(parser.PrimaryWord(parser.Word("metric{c:d}"))),
        parser.Div,
      ),
      "metric{a:b} / metric{c:d}",
    ),
  ]
  |> list.each(fn(pair) {
    let #(exp, expected) = pair
    generator.exp_to_string(exp) |> should.equal(expected)
  })
}

pub fn exp_to_string_parsed_expressions_test() {
  // Tests that parse strings and verify output
  [
    // path with dots in field name
    #(
      "http.url_details.path:/v1/users/members",
      "http.url_details.path:/v1/users/members",
    ),
    // path ending with closing brace
    #("path:/v1/users/passwords/reset}", "path:/v1/users/passwords/reset}"),
    // full datadog query path pattern
    #(
      "http.url_details.path:/v1/users/passwords/reset",
      "http.url_details.path:/v1/users/passwords/reset",
    ),
    // datadog query pattern with braces
    #(
      "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}",
      "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}",
    ),
    // path with underscores in last segment
    #(
      "http.url_details.path:/oauth/access_token",
      "http.url_details.path:/oauth/access_token",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    let assert Ok(parser.ExpContainer(exp)) = parser.parse_expr(input)
    generator.exp_to_string(exp) |> should.equal(expected)
  })
}

// ==== Operator to Datadog Query ====
// * ✅ Addition
// * ✅ Subtraction
// * ✅ Multiplication
// * ✅ Division
pub fn operator_to_datadog_query_test() {
  [
    #(parser.Add, "+"),
    #(parser.Sub, "-"),
    #(parser.Mul, "*"),
    #(parser.Div, "/"),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair

    generator.operator_to_datadog_query(input)
    |> should.equal(expected)
  })
}

// ==== substitute_words ====
// * ✅ substitutes single word
// * ✅ substitutes multiple words in expression
// * ✅ leaves unknown words unchanged
// * ✅ handles nested parenthesized expressions
pub fn substitute_words_test() {
  [
    // substitutes single word
    #(
      "numerator",
      dict.from_list([#("numerator", "sum:http.requests{status:2xx}")]),
      "sum:http.requests{status:2xx}",
    ),
    // substitutes multiple words in expression
    #(
      "good / total",
      dict.from_list([
        #("good", "sum:http.requests{status:2xx}"),
        #("total", "sum:http.requests{*}"),
      ]),
      "sum:http.requests{status:2xx} / sum:http.requests{*}",
    ),
    // leaves unknown words unchanged
    #(
      "good / unknown",
      dict.from_list([#("good", "sum:http.requests{status:2xx}")]),
      "sum:http.requests{status:2xx} / unknown",
    ),
    // handles nested parenthesized expressions
    #(
      "(good + partial) / total",
      dict.from_list([
        #("good", "sum:http.requests{status:2xx}"),
        #("partial", "sum:http.requests{status:3xx}"),
        #("total", "sum:http.requests{*}"),
      ]),
      "(sum:http.requests{status:2xx} + sum:http.requests{status:3xx}) / sum:http.requests{*}",
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input, substitutions, expected) = tuple
    let assert Ok(parser.ExpContainer(exp)) = parser.parse_expr(input)
    generator.substitute_words(exp, substitutions)
    |> generator.exp_to_string
    |> should.equal(expected)
  })
}

// ==== resolve_slo_query ====
// * ✅ simple numerator/denominator
// * ✅ complex expression with addition
pub fn resolve_slo_query_test() {
  [
    // simple numerator/denominator
    #(
      "numerator / denominator",
      dict.from_list([
        #("numerator", "sum:http.requests{status:2xx}"),
        #("denominator", "sum:http.requests{*}"),
      ]),
      #("sum:http.requests{status:2xx}", "sum:http.requests{*}"),
    ),
    // complex expression with addition
    #(
      "(good + partial) / total",
      dict.from_list([
        #("good", "sum:http.requests{status:2xx}"),
        #("partial", "sum:http.requests{status:3xx}"),
        #("total", "sum:http.requests{*}"),
      ]),
      #(
        "(sum:http.requests{status:2xx} + sum:http.requests{status:3xx})",
        "sum:http.requests{*}",
      ),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(value_expr, substitutions, expected) = tuple
    generator.resolve_slo_query(value_expr, substitutions)
    |> should.equal(expected)
  })
}
