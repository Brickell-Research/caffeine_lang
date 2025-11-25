import caffeine_lang_v2/parser
import gleam/dict
import gleam/list
import gleeunit/should

// ==== Helpers ====
pub fn assert_error_on_parse(file_path, error_string) {
  parser.parse_blueprint_specification(file_path_base(file_path))
  |> should.equal(Error(error_string))
}

pub fn file_path_base(file_path) {
  "test/caffeine_lang_v2/artifacts/parser_tests/" <> file_path <> ".yml"
}

// ==== Tests ====
// ==== Happy Path ====
// * ✅ single blueprint
// * ✅ multiple blueprints
pub fn parse_blueprint_specification_test() {
  //single
  let expected_blueprints = [
    parser.Blueprint(
      name: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", parser.String),
        #("environment", parser.String),
      ]),
      queries: dict.from_list([
        #(
          "numerator",
          "sum.app.requests{operation:${gql_operation},status:success,environment:${environment}}.as_count()",
        ),
        #(
          "denominator",
          "sum.app.requests{operation:${gql_operation},environment:${environment}}.as_count()",
        ),
      ]),
      value: "numerator / denominator",
    ),
  ]

  parser.parse_blueprint_specification(file_path_base("happy_path_single"))
  |> should.equal(Ok(expected_blueprints))

  // multiple
  let expected_blueprints = [
    parser.Blueprint(
      name: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", parser.String),
        #("environment", parser.String),
      ]),
      queries: dict.from_list([
        #(
          "numerator",
          "sum.app.requests{operation:${gql_operation},status:success,environment:${environment}}.as_count()",
        ),
        #(
          "denominator",
          "sum.app.requests{operation:${gql_operation},environment:${environment}}.as_count()",
        ),
      ]),
      value: "numerator / denominator",
    ),
    parser.Blueprint(
      name: "latency_http",
      inputs: dict.from_list([
        #("endpoint", parser.String),
        #("status_codes", parser.NonEmptyList(parser.String)),
        #("percentile", parser.Decimal),
      ]),
      queries: dict.from_list([
        #(
          "latency_query",
          "percentile.app.latency{endpoint:${endpoint},status:${status_codes}}.at(${percentile})",
        ),
      ]),
      value: "latency_query",
    ),
  ]

  parser.parse_blueprint_specification(file_path_base("happy_path_multiple"))
  |> should.equal(Ok(expected_blueprints))
}

// ==== Empty ====
// * ✅ blueprint
// * ✅ name
// * ✅ inputs (empty dictionary)
// * ✅ queries (empty dictionary)
// * ✅ value
pub fn parse_blueprint_specification_empty_test() {
  // blueprints
  let assert Ok(blueprints) =
    parser.parse_blueprint_specification(file_path_base("empty_blueprints"))
  blueprints |> should.equal(list.new())

  list.each(
    [
      #("empty_name", "Expected name to be a string"),
      #("empty_inputs", "Expected inputs to be a map"),
      #("empty_queries", "Expected queries to be a map"),
      #("empty_value", "Expected value to be a string"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Missing ====
// * ✅ blueprint (a.k.a. empty file)
// * ✅ name
// * ✅ inputs
// * ✅ queries
// * ✅ value
pub fn parse_blueprint_specification_missing_test() {
  list.each(
    [
      #("empty_file", "Empty YAML file: " <> file_path_base("empty_file")),
      #("missing_name", "Missing name"),
      #("missing_value", "Missing value"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )

  // queries
  let assert Ok([first, ..]) =
    parser.parse_blueprint_specification(file_path_base("missing_queries"))
  first.queries |> should.equal(dict.new())

  // inputs
  let assert Ok([first, ..]) =
    parser.parse_blueprint_specification(file_path_base("missing_inputs"))
  first.inputs |> should.equal(dict.new())
}

// ==== Duplicates ====
// * 🚧 name (all blueprints must be unique)
// * ❌ inputs (all inputs must have unique labels) - LIMITATION: glaml silently overrides
// * ❌ queries (all queries must have unique labels) - LIMITATION: glaml silently overrides
pub fn parse_blueprint_specification_duplicates_test() {
  list.each(
    [
      #(
        "duplicate_names",
        "Duplicate blueprint names detected: success_rate_graphql",
      ),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Wrong Types ====
// * 🚧 blueprint
// * ✅ name
// * ✅ inputs
//  * ✅ inputs is a map
//  * ✅ each input's value is an Accepted Type
// * ✅ queries
//  * ✅ queries is a map
//  * ✅ each query is a strings
// * ✅ value
pub fn parse_blueprint_specification_wrong_type_test() {
  list.each(
    [
      // #("wrong_type_blueprints", "Expected name to be a string"), # wrong
      #("wrong_type_name", "Expected name to be a string"),
      #("wrong_type_value", "Expected value to be a string"),
      #("wrong_type_queries", "Expected queries to be a map"),
      #(
        "wrong_type_queries_value",
        "Expected inputs entries to be string key-value pairs",
      ),
      #("wrong_type_inputs", "Expected inputs to be a map"),
      #("wrong_type_inputs_value", "Invalid type: NotARealType"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}
