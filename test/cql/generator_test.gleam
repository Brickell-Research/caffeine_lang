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
