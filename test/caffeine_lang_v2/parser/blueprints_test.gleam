import caffeine_lang_v2/common.{Float, NonEmptyList, String}
import caffeine_lang_v2/parser/blueprints
import gleam/dict
import gleam/list
import gleeunit/should

// ==== Helpers ====
pub fn assert_error_on_parse(file_path, error_string) {
  blueprints.parse(file_path_base(file_path))
  |> should.equal(Error(error_string))
}

pub fn file_path_base(file_path) {
  "test/caffeine_lang_v2/artifacts/parser_tests/blueprints/"
  <> file_path
  <> ".yml"
}

// ==== Tests - Blueprints ====
// ==== Happy Path ====
// * ❌ none
// * ✅ single blueprint
// * ✅ multiple blueprints
pub fn parse_test() {
  //single
  let expected_blueprints = [
    blueprints.make_blueprint(
      name: "success_rate_graphql",
      artifact: "datadog_sli",
      params: dict.from_list([
        #("gql_operation", String),
        #("environment", String),
      ]),
      inputs: dict.from_list([
        #(
          "numerator",
          "sum.app.requests{operation:${gql_operation},status:success,environment:${environment}}.as_count()",
        ),
        #(
          "denominator",
          "sum.app.requests{operation:${gql_operation},environment:${environment}}.as_count()",
        ),
      ]),
    ),
  ]

  blueprints.parse(file_path_base("happy_path_single"))
  |> should.equal(Ok(expected_blueprints))

  // multiple
  let expected_blueprints = [
    blueprints.make_blueprint(
      name: "success_rate_graphql",
      artifact: "datadog_sli",
      params: dict.from_list([
        #("gql_operation", String),
        #("environment", String),
      ]),
      inputs: dict.from_list([
        #(
          "numerator",
          "sum.app.requests{operation:${gql_operation},status:success,environment:${environment}}.as_count()",
        ),
        #(
          "denominator",
          "sum.app.requests{operation:${gql_operation},environment:${environment}}.as_count()",
        ),
      ]),
    ),
    blueprints.make_blueprint(
      name: "latency_http",
      artifact: "datadog_sli",
      params: dict.from_list([
        #("endpoint", String),
        #("status_codes", NonEmptyList(String)),
        #("percentile", Float),
      ]),
      inputs: dict.from_list([
        #(
          "latency_query",
          "percentile.app.latency{endpoint:${endpoint},status:${status_codes}}.at(${percentile})",
        ),
      ]),
    ),
  ]

  blueprints.parse(file_path_base("happy_path_multiple"))
  |> should.equal(Ok(expected_blueprints))
}

// ==== Empty ====
// * ✅ params (empty dictionary)
// * ✅ inputs (empty dictionary)
// * ✅ content (empty file)
// * ✅ blueprint
// * ✅ name
// * ✅ artifact
pub fn parse_empty_test() {
  list.each(
    [
      #("empty_params", "Expected params to be non-empty"),
      #("empty_inputs", "Expected inputs to be non-empty"),
      #("empty_file", "Empty YAML file: " <> file_path_base("empty_file")),
      #("empty_blueprints", "blueprints is empty"),
      #("empty_name", "Expected name to be non-empty"),
      #("empty_artifact", "Expected artifact to be non-empty"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Missing ====
// * ✅ name
// * ✅ artifact
// * ✅ params
// * ✅ inputs
pub fn parse_missing_test() {
  list.each(
    [
      #("missing_name", "Missing name"),
      #("missing_artifact", "Missing artifact"),
      #("missing_params", "Missing params"),
      #("missing_inputs", "Missing inputs"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Duplicates ====
// * ✅ name (all blueprints must be unique)
// * ✅ params (all params must have unique labels)
// * ✅ inputs (all inputs must have unique labels)
pub fn parse_duplicates_test() {
  list.each(
    [
      #(
        "duplicate_names",
        "Duplicate blueprint names detected: success_rate_graphql",
      ),
      #("duplicate_params", "Duplicate keys detected for params: gql_operation"),
      #("duplicate_inputs", "Duplicate keys detected for inputs: numerator"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Wrong Types ====
// * ✅ blueprint
// * ✅ name
// * ✅ artifact
// * ✅ params
//  * ✅ params is a map
//  * ✅ each param's value is an Accepted Type
// * ✅ inputs
//  * ✅ inputs is a map
//  * ✅ each input is a string
pub fn parse_wrong_type_test() {
  list.each(
    [
      // wrong_type_blueprints is weird, but reasonable enough
      #("wrong_type_blueprints", "blueprints is empty"),
      #("wrong_type_name", "Expected name to be a string, but found list"),
      #(
        "wrong_type_artifact",
        "Expected artifact to be a string, but found list",
      ),
      #("wrong_type_params", "Expected params to be a map, but found string"),
      #("wrong_type_params_value", "Invalid type: NotARealType"),
      #("wrong_type_inputs", "Expected inputs to be a map, but found string"),
      #(
        "wrong_type_inputs_value",
        "Expected inputs to be a map of strings, but found map with non-string keys or values",
      ),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}
