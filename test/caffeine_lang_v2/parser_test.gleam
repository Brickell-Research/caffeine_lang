import caffeine_lang_v2/parser
import gleam/dict
import gleam/list
import gleeunit/should

// ==== Helpers ====
pub fn assert_error_on_parse_blueprint(file_path, error_string) {
  parser.parse_blueprint_specification(file_path_base_blueprints(file_path))
  |> should.equal(Error(error_string))
}

pub fn file_path_base_blueprints(file_path) {
  "test/caffeine_lang_v2/artifacts/parser_tests/blueprints/"
  <> file_path
  <> ".yml"
}

pub fn assert_error_on_parse_expectation(file_path, error_string) {
  parser.parse_service_expectation_invocation(file_path_base_expectations(
    file_path,
  ))
  |> should.equal(Error(error_string))
}

pub fn file_path_base_expectations(file_path) {
  "test/caffeine_lang_v2/artifacts/parser_tests/expectations/"
  <> file_path
  <> ".yml"
}

// ==== Tests - Blueprints ====
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

  parser.parse_blueprint_specification(file_path_base_blueprints(
    "happy_path_single",
  ))
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

  parser.parse_blueprint_specification(file_path_base_blueprints(
    "happy_path_multiple",
  ))
  |> should.equal(Ok(expected_blueprints))
}

// ==== Empty ====
// * ✅ inputs (empty dictionary)
// * ✅ queries (empty dictionary)
// * ✅ content (empty file)
// * ✅ blueprint
// * ✅ name
// * ✅ value
pub fn parse_blueprint_specification_empty_test() {
  // empty inputs and queries are OK (treated as empty dict)
  let assert Ok([first, ..]) =
    parser.parse_blueprint_specification(file_path_base_blueprints(
      "empty_inputs",
    ))
  first.inputs |> should.equal(dict.new())

  let assert Ok([first, ..]) =
    parser.parse_blueprint_specification(file_path_base_blueprints(
      "empty_queries",
    ))
  first.queries |> should.equal(dict.new())

  list.each(
    [
      #(
        "empty_file",
        "Empty YAML file: " <> file_path_base_blueprints("empty_file"),
      ),
      #("empty_blueprints", "blueprints is empty"),
      #("empty_name", "Expected name to be non-empty"),
      #("empty_value", "Expected value to be non-empty"),
    ],
    fn(testcase) { assert_error_on_parse_blueprint(testcase.0, testcase.1) },
  )
}

// ==== Missing ====
// * ✅ name
// * ✅ inputs
// * ✅ queries
// * ✅ value
pub fn parse_blueprint_specification_missing_test() {
  list.each(
    [
      #("missing_name", "Missing name"),
      #("missing_inputs", "Missing inputs"),
      #("missing_queries", "Missing queries"),
      #("missing_value", "Missing value"),
    ],
    fn(testcase) { assert_error_on_parse_blueprint(testcase.0, testcase.1) },
  )
}

// ==== Duplicates ====
// * ✅ name (all blueprints must be unique)
// * ✅ inputs (all inputs must have unique labels) - LIMITATION: glaml silently overrides
// * ✅ queries (all queries must have unique labels) - LIMITATION: glaml silently overrides
pub fn parse_blueprint_specification_duplicates_test() {
  list.each(
    [
      #(
        "duplicate_names",
        "Duplicate blueprint names detected: success_rate_graphql",
      ),
      #("duplicate_inputs", "Duplicate keys detected for inputs: gql_operation"),
      #("duplicate_queries", "Duplicate keys detected for queries: numerator"),
    ],
    fn(testcase) { assert_error_on_parse_blueprint(testcase.0, testcase.1) },
  )
}

// ==== Wrong Types ====
// * ✅ blueprint
// * ✅ name
// * ✅ queries
//  * ✅ queries is a map
//  * ✅ each query is a strings
// * ✅ inputs
//  * ✅ inputs is a map
//  * ✅ each input's value is an Accepted Type
// * ✅ value
pub fn parse_blueprint_specification_wrong_type_test() {
  list.each(
    [
      // wrong_type_blueprints is weird, but reasonable enough 🤷‍♂️
      #("wrong_type_blueprints", "blueprints is empty"),
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
    fn(testcase) { assert_error_on_parse_blueprint(testcase.0, testcase.1) },
  )
}

// ==== Test - Expectations ====
// ==== Happy Path ====
// * ✅ single
// * ✅ multiple
pub fn parse_service_expectation_invocation_test() {
  // single
  let expected_expectations = [
    parser.ServiceExpectation(
      name: "Some operation succeeds in production",
      blueprint: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", "some_operation"),
        #("environment", "production"),
      ]),
      threshold: 99.9,
      window_in_days: 10,
    ),
  ]

  parser.parse_service_expectation_invocation(file_path_base_expectations(
    "happy_path_single",
  ))
  |> should.equal(Ok(expected_expectations))

  // multiple
  let expected_expectations = [
    parser.ServiceExpectation(
      name: "Some operation succeeds in production",
      blueprint: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", "some_operation"),
        #("environment", "production"),
      ]),
      threshold: 99.9,
      window_in_days: 10,
    ),
    parser.ServiceExpectation(
      name: "Some other operation succeeds in production",
      blueprint: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", "some_other_operation"),
        #("environment", "production"),
      ]),
      threshold: 99.0,
      window_in_days: 30,
    ),
  ]

  parser.parse_service_expectation_invocation(file_path_base_expectations(
    "happy_path_multiple",
  ))
  |> should.equal(Ok(expected_expectations))
}

// ==== Empty ====
// * ✅ inputs - (empty dictionary)
// * ✅ expectations
// * ✅ name
// * ✅ blueprint
// * ✅ threshold
// * ✅ window_in_days
pub fn parse_service_expectation_invocation_empty_test() {
  // empty inputs is OK (treated as empty dict)
  let assert Ok([first, ..]) =
    parser.parse_service_expectation_invocation(file_path_base_expectations(
      "empty_inputs",
    ))
  first.inputs |> should.equal(dict.new())

  list.each(
    [
      #("empty_expectations", "expectations is empty"),
      #("empty_name", "Expected name to be non-empty"),
      #("empty_blueprint", "Expected blueprint to be non-empty"),
      #("empty_threshold", "Expected threshold to be non-empty"),
      #("empty_window_in_days", "Expected window_in_days to be non-empty"),
    ],
    fn(testcase) { assert_error_on_parse_expectation(testcase.0, testcase.1) },
  )
}

// ==== Missing ====
// * ✅ content (empty file)
// * ✅ expectations
// * ✅ name
// * ✅ blueprint
// * ✅ inputs
// * ✅ threshold
// * ✅ window_in_days
pub fn parse_service_expectation_invocation_missing_test() {
  list.each(
    [
      #(
        "empty_file",
        "Empty YAML file: " <> file_path_base_expectations("empty_file"),
      ),
      #("empty_expectations", "expectations is empty"),
      #("missing_name", "Missing name"),
      #("missing_blueprint", "Missing blueprint"),
      #("missing_inputs", "Missing inputs"),
      #("missing_threshold", "Missing threshold"),
      #("missing_window_in_days", "Missing window_in_days"),
    ],
    fn(testcase) { assert_error_on_parse_expectation(testcase.0, testcase.1) },
  )
}

// ==== Duplicates ====
// * ✅ name
// * ✅ inputs (all inputs must have unique labels) - LIMITATION: glaml silently overrides
pub fn parse_service_expectation_invocation_duplicates_test() {
  list.each(
    [
      #(
        "duplicate_names",
        "Duplicate blueprint names detected: Some operation succeeds in production",
      ),
      #(
        "duplicate_inputs",
        "Duplicate keys detected for inputs: environment, gql_operation",
      ),
    ],
    fn(testcase) { assert_error_on_parse_expectation(testcase.0, testcase.1) },
  )
}

// ==== Wrong Types ====
// * ✅ expectations
// * ✅ name
// * ✅ blueprint
// * ✅ inputs (we will initially interpret all as String and later attempt to coalesce to the proper type)
// * ✅ threshold
// * ✅ window_in_days
pub fn parse_service_expectation_invocation_wrong_type_test() {
  list.each(
    [
      // wrong_type_expectations is weird, but reasonable enough 🤷‍♂️
      #("wrong_type_expectations", "expectations is empty"),
      #("wrong_type_name", "Expected name to be a string"),
      #("wrong_type_blueprint", "Expected blueprint to be a string"),
      #("wrong_type_inputs", "Expected inputs to be a map"),
      #("wrong_type_threshold", "Expected threshold to be a float"),
      #("wrong_type_window_in_days", "Expected window_in_days to be an integer"),
    ],
    fn(testcase) { assert_error_on_parse_expectation(testcase.0, testcase.1) },
  )
}
