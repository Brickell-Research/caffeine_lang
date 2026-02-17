import caffeine_query_language/ast
import caffeine_query_language/generator
import caffeine_query_language/parser
import caffeine_query_language/printer
import gleam/dict
import gleam/list
import gleeunit/should
import terra_madre/hcl
import test_helpers

// ==== resolve_slo_to_hcl ====
// good_over_total
// * ✅ simple good over total query returns MetricSlo with query block
// time_slice
// * ✅ time_slice returns TimeSliceSlo with sli_specification block
// * ✅ time_slice with formula expression generates multiple metric_query blocks
pub fn resolve_slo_to_hcl_test() {
  // simple good over total query returns MetricSlo with query block
  {
    let assert Ok(generator.ResolvedSloHcl(slo_type, blocks)) =
      generator.resolve_slo_to_hcl(
        "numerator / denominator",
        dict.from_list([
          #("numerator", "sum:http.requests{status:2xx}"),
          #("denominator", "sum:http.requests{*}"),
        ]),
      )

    slo_type |> should.equal(generator.MetricSlo)
    blocks |> list.length |> should.equal(1)

    let assert [query_block] = blocks
    query_block.type_ |> should.equal("query")
    dict.get(query_block.attributes, "numerator")
    |> should.equal(Ok(hcl.StringLiteral("sum:http.requests{status:2xx}")))
    dict.get(query_block.attributes, "denominator")
    |> should.equal(Ok(hcl.StringLiteral("sum:http.requests{*}")))
  }

  // time_slice returns TimeSliceSlo with sli_specification block
  {
    let assert Ok(generator.ResolvedSloHcl(slo_type, blocks)) =
      generator.resolve_slo_to_hcl(
        "time_slice(avg:system.cpu{env:production} > 99.5 per 300s)",
        dict.new(),
      )

    slo_type |> should.equal(generator.TimeSliceSlo)
    blocks |> list.length |> should.equal(1)

    let assert [sli_spec_block] = blocks
    sli_spec_block.type_ |> should.equal("sli_specification")

    // Check nested time_slice block exists
    sli_spec_block.blocks |> list.length |> should.equal(1)
    let assert [time_slice_block] = sli_spec_block.blocks
    time_slice_block.type_ |> should.equal("time_slice")
    dict.get(time_slice_block.attributes, "comparator")
    |> should.equal(Ok(hcl.StringLiteral(">")))
    dict.get(time_slice_block.attributes, "query_interval_seconds")
    |> should.equal(Ok(hcl.IntLiteral(300)))
    dict.get(time_slice_block.attributes, "threshold")
    |> should.equal(Ok(hcl.FloatLiteral(99.5)))
  }

  // time_slice with formula expression generates multiple metric_query blocks
  {
    let assert Ok(generator.ResolvedSloHcl(slo_type, blocks)) =
      generator.resolve_slo_to_hcl(
        "time_slice((build_time + deploy_time) >= 600000 per 5m)",
        dict.from_list([
          #(
            "build_time",
            "sum:circleci.completed_build_time.avg{job_name:build-prod}",
          ),
          #(
            "deploy_time",
            "sum:circleci.completed_build_time.avg{job_name:deploy-prod}",
          ),
        ]),
      )

    slo_type |> should.equal(generator.TimeSliceSlo)
    blocks |> list.length |> should.equal(1)

    let assert [sli_spec_block] = blocks
    sli_spec_block.type_ |> should.equal("sli_specification")

    // Check nested time_slice block
    let assert [time_slice_block] = sli_spec_block.blocks
    time_slice_block.type_ |> should.equal("time_slice")
    dict.get(time_slice_block.attributes, "comparator")
    |> should.equal(Ok(hcl.StringLiteral(">=")))
    dict.get(time_slice_block.attributes, "threshold")
    |> should.equal(Ok(hcl.FloatLiteral(600_000.0)))

    // Check the outer query block contains formula + 2 inner query blocks
    let assert [outer_query_block] = time_slice_block.blocks
    outer_query_block.type_ |> should.equal("query")
    // Should have: 1 formula block + 2 query blocks (one per metric)
    outer_query_block.blocks |> list.length |> should.equal(3)

    // Find the formula block
    let formula_blocks =
      outer_query_block.blocks |> list.filter(fn(b) { b.type_ == "formula" })
    formula_blocks |> list.length |> should.equal(1)
    let assert [formula_block] = formula_blocks
    // Outer parentheses are stripped from the formula expression
    dict.get(formula_block.attributes, "formula_expression")
    |> should.equal(Ok(hcl.StringLiteral("build_time + deploy_time")))

    // Find the inner query blocks (each contains a metric_query)
    let inner_query_blocks =
      outer_query_block.blocks |> list.filter(fn(b) { b.type_ == "query" })
    inner_query_blocks |> list.length |> should.equal(2)

    // Extract metric_query blocks and verify their names
    let metric_names =
      inner_query_blocks
      |> list.flat_map(fn(qb) { qb.blocks })
      |> list.filter(fn(b) { b.type_ == "metric_query" })
      |> list.filter_map(fn(mq) {
        case dict.get(mq.attributes, "name") {
          Ok(hcl.StringLiteral(name)) -> Ok(name)
          _ -> Error(Nil)
        }
      })

    // Should have both build_time and deploy_time
    metric_names |> list.contains("build_time") |> should.be_true
    metric_names |> list.contains("deploy_time") |> should.be_true
  }
}

// ==== exp_to_string ====
// path expressions (manually constructed ASTs)
// * ✅ path with slashes (no spaces)
// * ✅ path with multiple segments
// * ✅ path with wildcards
// * ✅ normal division (with spaces)
// * ✅ division with query braces (with spaces)
// parsed expressions
// * ✅ path with dots in field name
// * ✅ path ending with closing brace
// * ✅ full datadog query path pattern
// * ✅ datadog query pattern with braces
// * ✅ path with underscores in last segment
pub fn exp_to_string_test() {
  // path expressions (manually constructed ASTs)
  [
    // path with slashes (no spaces) - metric{path:/v1/users}
    #(
      "path with slashes (no spaces)",
      ast.OperatorExpr(
        ast.Primary(ast.PrimaryWord(ast.Word("metric{path:"))),
        ast.OperatorExpr(
          ast.Primary(ast.PrimaryWord(ast.Word("v1"))),
          ast.Primary(ast.PrimaryWord(ast.Word("users}"))),
          ast.Div,
        ),
        ast.Div,
      ),
      "metric{path:/v1/users}",
    ),
    // path with multiple segments - path:/v1/users/passwords/reset
    #(
      "path with multiple segments",
      ast.OperatorExpr(
        ast.Primary(ast.PrimaryWord(ast.Word("path:"))),
        ast.OperatorExpr(
          ast.OperatorExpr(
            ast.OperatorExpr(
              ast.Primary(ast.PrimaryWord(ast.Word("v1"))),
              ast.Primary(ast.PrimaryWord(ast.Word("users"))),
              ast.Div,
            ),
            ast.Primary(ast.PrimaryWord(ast.Word("passwords"))),
            ast.Div,
          ),
          ast.Primary(ast.PrimaryWord(ast.Word("reset"))),
          ast.Div,
        ),
        ast.Div,
      ),
      "path:/v1/users/passwords/reset",
    ),
    // path with wildcards - path:/v1/users/forgot*
    #(
      "path with wildcards",
      ast.OperatorExpr(
        ast.Primary(ast.PrimaryWord(ast.Word("path:"))),
        ast.OperatorExpr(
          ast.OperatorExpr(
            ast.Primary(ast.PrimaryWord(ast.Word("v1"))),
            ast.Primary(ast.PrimaryWord(ast.Word("users"))),
            ast.Div,
          ),
          ast.Primary(ast.PrimaryWord(ast.Word("forgot*"))),
          ast.Div,
        ),
        ast.Div,
      ),
      "path:/v1/users/forgot*",
    ),
    // normal division (with spaces)
    #(
      "normal division (with spaces)",
      ast.OperatorExpr(
        ast.Primary(ast.PrimaryWord(ast.Word("metric_a"))),
        ast.Primary(ast.PrimaryWord(ast.Word("metric_b"))),
        ast.Div,
      ),
      "metric_a / metric_b",
    ),
    // division with query braces (with spaces)
    #(
      "division with query braces (with spaces)",
      ast.OperatorExpr(
        ast.Primary(ast.PrimaryWord(ast.Word("metric{a:b}"))),
        ast.Primary(ast.PrimaryWord(ast.Word("metric{c:d}"))),
        ast.Div,
      ),
      "metric{a:b} / metric{c:d}",
    ),
  ]
  |> test_helpers.table_test_1(printer.exp_to_string)

  // parsed expressions
  [
    // path with dots in field name
    #(
      "path with dots in field name",
      "http.url_details.path:/v1/users/members",
      "http.url_details.path:/v1/users/members",
    ),
    // path ending with closing brace
    #(
      "path ending with closing brace",
      "path:/v1/users/passwords/reset}",
      "path:/v1/users/passwords/reset}",
    ),
    // full datadog query path pattern
    #(
      "full datadog query path pattern",
      "http.url_details.path:/v1/users/passwords/reset",
      "http.url_details.path:/v1/users/passwords/reset",
    ),
    // datadog query pattern with braces
    #(
      "datadog query pattern with braces",
      "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}",
      "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}",
    ),
    // path with underscores in last segment
    #(
      "path with underscores in last segment",
      "http.url_details.path:/oauth/access_token",
      "http.url_details.path:/oauth/access_token",
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let assert Ok(exp) = parser.parse_expr(input)
    printer.exp_to_string(exp)
  })
}

// ==== operator_to_string ====
// * ✅ Addition
// * ✅ Subtraction
// * ✅ Multiplication
// * ✅ Division
pub fn operator_to_string_test() {
  [
    #("Addition", ast.Add, "+"),
    #("Subtraction", ast.Sub, "-"),
    #("Multiplication", ast.Mul, "*"),
    #("Division", ast.Div, "/"),
  ]
  |> test_helpers.table_test_1(printer.operator_to_string)
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
      "substitutes single word",
      "numerator",
      dict.from_list([#("numerator", "sum:http.requests{status:2xx}")]),
      "sum:http.requests{status:2xx}",
    ),
    // substitutes multiple words in expression
    #(
      "substitutes multiple words in expression",
      "good / total",
      dict.from_list([
        #("good", "sum:http.requests{status:2xx}"),
        #("total", "sum:http.requests{*}"),
      ]),
      "sum:http.requests{status:2xx} / sum:http.requests{*}",
    ),
    // leaves unknown words unchanged
    #(
      "leaves unknown words unchanged",
      "good / unknown",
      dict.from_list([#("good", "sum:http.requests{status:2xx}")]),
      "sum:http.requests{status:2xx} / unknown",
    ),
    // handles nested parenthesized expressions
    #(
      "handles nested parenthesized expressions",
      "(good + partial) / total",
      dict.from_list([
        #("good", "sum:http.requests{status:2xx}"),
        #("partial", "sum:http.requests{status:3xx}"),
        #("total", "sum:http.requests{*}"),
      ]),
      "(sum:http.requests{status:2xx} + sum:http.requests{status:3xx}) / sum:http.requests{*}",
    ),
  ]
  |> test_helpers.table_test_2(fn(input, substitutions) {
    let assert Ok(exp) = parser.parse_expr(input)
    generator.substitute_words(exp, substitutions)
    |> printer.exp_to_string
  })
}

// ==== extract_words ====
// * ✅ single word
// * ✅ multiple words in expression
// * ✅ words in nested parentheses
// * ✅ complex formula
pub fn extract_words_test() {
  [
    #("query1", ["query1"]),
    #("build_time + deploy_time", ["build_time", "deploy_time"]),
    #("(a + b) * c", ["a", "b", "c"]),
    #("(build_time + deploy_time) / total", [
      "build_time",
      "deploy_time",
      "total",
    ]),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    let assert Ok(exp) = parser.parse_expr(input)
    let words = generator.extract_words(exp)
    // Check all expected words are present (order may vary)
    expected |> list.each(fn(w) { words |> list.contains(w) |> should.be_true })
    words |> list.length |> should.equal(list.length(expected))
  })
}

// ==== resolve_slo_to_expression ====
// * ✅ single word identity substitutes indicator value
// * ✅ division substitutes and renders as division
// * ✅ addition substitutes and renders as addition
// * ✅ multi-indicator composition substitutes all words
// * ❌ undefined indicator returns error
// * ❌ partially undefined indicators returns error listing missing
// * ❌ time_slice returns error
pub fn resolve_slo_to_expression_test() {
  // single word identity substitutes indicator value
  generator.resolve_slo_to_expression(
    "sli",
    dict.from_list([#("sli", "LT($\"status_code\", 500)")]),
  )
  |> should.equal(Ok("LT($\"status_code\", 500)"))

  // division substitutes and renders as division
  generator.resolve_slo_to_expression(
    "good / total",
    dict.from_list([#("good", "query1"), #("total", "query2")]),
  )
  |> should.equal(Ok("query1 / query2"))

  // addition substitutes and renders as addition
  generator.resolve_slo_to_expression(
    "a + b",
    dict.from_list([#("a", "val1"), #("b", "val2")]),
  )
  |> should.equal(Ok("val1 + val2"))

  // multi-indicator composition substitutes all words
  generator.resolve_slo_to_expression(
    "(latency + errors) / total",
    dict.from_list([
      #("latency", "lat_query"),
      #("errors", "err_query"),
      #("total", "total_query"),
    ]),
  )
  |> should.equal(Ok("(lat_query + err_query) / total_query"))

  // undefined indicator returns error
  generator.resolve_slo_to_expression("sli", dict.new())
  |> should.equal(Error("evaluation references undefined indicators: sli"))

  // partially undefined indicators returns error listing missing
  generator.resolve_slo_to_expression(
    "(a + b) / c",
    dict.from_list([#("a", "val1")]),
  )
  |> should.equal(Error("evaluation references undefined indicators: b, c"))

  // time_slice returns error
  generator.resolve_slo_to_expression("time_slice(Q > 1 per 1s)", dict.new())
  |> should.be_error
}
