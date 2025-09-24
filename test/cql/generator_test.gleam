import caffeine_lang/cql/generator
import caffeine_lang/cql/parser
import caffeine_lang/cql/resolver
import startest/expect

pub fn datadog_generator_test() {
  let query = "A + B / C"
  let expected =
    "query {\n    numerator = \"A + B\"\n    denominator = \"C\"\n  }\n"

  let assert Ok(parsed) = parser.parse_expr(query)
  let assert Ok(resolved) = resolver.resolve_primitives(parsed)
  let actual = generator.generate_datadog_query(resolved)
  expect.to_equal(actual, expected)
}
