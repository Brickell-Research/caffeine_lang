import cql/generator
import cql/parser
import cql/resolver
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn generate_datadog_query_test() {
  describe("generate_datadog_query", fn() {
    it("should generate a query for a good over bad expression", fn() {
      let assert Ok(parsed) = parser.parse_expr("(A + B) / C")
      let assert Ok(resolved) = resolver.resolve_primitives(parsed)

      generator.generate_datadog_query(resolved)
      |> gleeunit.equal(
        "query {
    numerator = \"A + B\"
    denominator = \"C\"
  }
",
      )
    })

    it(
      "should generate a query for a nested and complex good over bad expression",
      fn() {
        let assert Ok(parsed) =
          parser.parse_expr("((A - G) + B) / (C + (D + E) * F)")
        let assert Ok(resolved) = resolver.resolve_primitives(parsed)

        generator.generate_datadog_query(resolved)
        |> gleeunit.equal(
          "query {
    numerator = \"(A - G) + B\"
    denominator = \"C + (D + E) * F\"
  }
",
        )
      },
    )
  })
}

pub fn exp_to_string_test() {
  describe("exp_to_string", fn() {
    describe("path handling", fn() {
      it("should not add spaces to URL paths with slashes", fn() {
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
        |> gleeunit.equal("metric{path:/v1/users}")
      })

      it("should handle paths with multiple segments", fn() {
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
        |> gleeunit.equal("path:/v1/users/passwords/reset")
      })

      it("should handle paths with wildcards", fn() {
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
        |> gleeunit.equal("path:/v1/users/forgot*")
      })

      it("should handle paths with dots in field name", fn() {
        // Parse the actual string to see what the parser generates
        let query_str = "http.url_details.path:/v1/users/members"

        case parser.parse_expr(query_str) {
          Ok(parser.ExpContainer(exp)) -> {
            let result = generator.exp_to_string(exp)

            // Path with dots in field name should remain intact
            result
            |> gleeunit.equal("http.url_details.path:/v1/users/members")
          }
          Error(_) -> {
            gleeunit.fail()
          }
        }
      })

      it("should handle paths ending with closing brace", fn() {
        // This simulates: {path:/v1/users/passwords/reset}
        let query_str = "path:/v1/users/passwords/reset}"

        case parser.parse_expr(query_str) {
          Ok(parser.ExpContainer(exp)) -> {
            let result = generator.exp_to_string(exp)

            // Path ending with } should remain intact
            result
            |> gleeunit.equal("path:/v1/users/passwords/reset}")
          }
          Error(_) -> {
            gleeunit.fail()
          }
        }
      })

      it("should handle full Datadog query path pattern", fn() {
        // The CQL parser treats AND as a word, not an operator
        // So we need to test just the path portion that actually gets parsed
        let path_only = "http.url_details.path:/v1/users/passwords/reset"

        case parser.parse_expr(path_only) {
          Ok(parser.ExpContainer(exp)) -> {
            let result = generator.exp_to_string(exp)
            result
            |> gleeunit.equal("http.url_details.path:/v1/users/passwords/reset")
          }
          Error(_) -> {
            gleeunit.fail()
          }
        }
      })

      it("should handle Datadog query pattern with braces", fn() {
        // The actual query has the fields inside braces: {field1, field2, path:/v1/users}
        // After comma-to-AND conversion: {field1 AND field2 AND path:/v1/users}
        // The CQL parser will parse this as a single word token with divisions in the path
        let query_str =
          "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}"

        case parser.parse_expr(query_str) {
          Ok(parser.ExpContainer(exp)) -> {
            let result = generator.exp_to_string(exp)
            result
            |> gleeunit.equal(
              "{env:production AND http.method:POST AND http.url_details.path:/v1/users/passwords/reset}",
            )
          }
          Error(_) -> {
            gleeunit.fail()
          }
        }
      })

      it("should handle paths with underscores in the last segment", fn() {
        let query_str = "http.url_details.path:/oauth/access_token"

        case parser.parse_expr(query_str) {
          Ok(parser.ExpContainer(exp)) -> {
            let result = generator.exp_to_string(exp)
            result
            |> gleeunit.equal("http.url_details.path:/oauth/access_token")
          }
          Error(_) -> {
            gleeunit.fail()
          }
        }
      })
    })

    describe("division handling", fn() {
      it("should add spaces to normal division operations", fn() {
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
        |> gleeunit.equal("metric_a / metric_b")
      })

      it("should add spaces to division with query braces", fn() {
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
        |> gleeunit.equal("metric{a:b} / metric{c:d}")
      })
    })
  })
}
