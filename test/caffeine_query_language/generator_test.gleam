import caffeine_query_language/ast
import caffeine_query_language/generator
import caffeine_query_language/parser
import caffeine_query_language/printer
import gleam/dict
import gleam/list
import gleeunit/should
import test_helpers

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

// ==== strip_outer_parens ====
// * ✅ strips balanced outer parens
// * ✅ leaves non-wrapping parens unchanged
// * ✅ non-parenthesized string unchanged
// * ✅ strips nested parens to one level
// * ✅ empty string
// * ✅ empty parens
// * ✅ trims whitespace before stripping
pub fn strip_outer_parens_test() {
  [
    #("strips balanced outer parens", "(a + b)", "a + b"),
    #("leaves non-wrapping parens unchanged", "(a + b) * c", "(a + b) * c"),
    #("non-parenthesized string unchanged", "hello", "hello"),
    #("strips nested parens to one level", "((a + b))", "(a + b)"),
    #("empty string", "", ""),
    #("empty parens", "()", ""),
    #("trims whitespace before stripping", "  (a + b)  ", "a + b"),
  ]
  |> test_helpers.table_test_1(printer.strip_outer_parens)
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
  [
    // single word identity substitutes indicator value
    #(
      "single word identity substitutes indicator value",
      "sli",
      dict.from_list([#("sli", "LT($\"status_code\", 500)")]),
      Ok("LT($\"status_code\", 500)"),
    ),
    // division substitutes and renders as division
    #(
      "division substitutes and renders as division",
      "good / total",
      dict.from_list([#("good", "query1"), #("total", "query2")]),
      Ok("query1 / query2"),
    ),
    // addition substitutes and renders as addition
    #(
      "addition substitutes and renders as addition",
      "a + b",
      dict.from_list([#("a", "val1"), #("b", "val2")]),
      Ok("val1 + val2"),
    ),
    // multi-indicator composition substitutes all words
    #(
      "multi-indicator composition substitutes all words",
      "(latency + errors) / total",
      dict.from_list([
        #("latency", "lat_query"),
        #("errors", "err_query"),
        #("total", "total_query"),
      ]),
      Ok("(lat_query + err_query) / total_query"),
    ),
    // undefined indicator returns error
    #(
      "undefined indicator returns error",
      "sli",
      dict.new(),
      Error("evaluation references undefined indicators: sli"),
    ),
    // partially undefined indicators returns error listing missing
    #(
      "partially undefined indicators returns error listing missing",
      "(a + b) / c",
      dict.from_list([#("a", "val1")]),
      Error("evaluation references undefined indicators: b, c"),
    ),
    // time_slice returns error
    #(
      "time_slice returns error",
      "time_slice(Q > 1 per 1s)",
      dict.new(),
      Error(
        "time_slice expressions are not supported for expression resolution",
      ),
    ),
  ]
  |> test_helpers.table_test_2(generator.resolve_slo_to_expression)
}
