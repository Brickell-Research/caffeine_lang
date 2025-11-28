import caffeine_lang_v2/common.{Boolean, Float, Integer, String}
import caffeine_lang_v2/parser/artifacts.{Artifact}
import gleam/dict
import gleam/list
import gleeunit/should

// ==== Helpers ====
pub fn assert_error_on_parse(file_path, error_string) {
  artifacts.parse(file_path_base(file_path))
  |> should.equal(Error(error_string))
}

pub fn file_path_base(file_path) {
  "test/caffeine_lang_v2/artifacts/parser_tests/artifacts/"
  <> file_path
  <> ".yml"
}

// ==== Tests - Artifacts ====
// ==== Happy Path ====
// * ✅ single artifact
// * ✅ multiple artifacts
pub fn parse_test() {
  // single
  let expected_artifacts = [
    Artifact(
      name: "datadog_sli",
      version: "1.0.0",
      base_params: dict.from_list([
        #("api_key", String),
        #("app_key", String),
      ]),
      params: dict.from_list([
        #("numerator", String),
        #("denominator", String),
        #("threshold", Float),
        #("window_in_days", Integer),
      ]),
    ),
  ]

  artifacts.parse(file_path_base("happy_path_single"))
  |> should.equal(Ok(expected_artifacts))

  // multiple
  let expected_artifacts = [
    Artifact(
      name: "datadog_sli",
      version: "1.0.0",
      base_params: dict.from_list([
        #("api_key", String),
        #("app_key", String),
      ]),
      params: dict.from_list([
        #("numerator", String),
        #("denominator", String),
        #("threshold", Float),
        #("window_in_days", Integer),
      ]),
    ),
    Artifact(
      name: "prometheus_alert",
      version: "2.0.0",
      base_params: dict.from_list([#("prometheus_url", String)]),
      params: dict.from_list([
        #("query", String),
        #("severity", String),
        #("enabled", Boolean),
      ]),
    ),
  ]

  artifacts.parse(file_path_base("happy_path_multiple"))
  |> should.equal(Ok(expected_artifacts))
}

// ==== Empty ====
// * ✅ base_params (empty dictionary)
// * ✅ params (empty dictionary)
// * ✅ content (empty file)
// * ✅ artifacts
// * ✅ name
// * ✅ version
pub fn parse_empty_test() {
  // empty base_params and params are OK (treated as empty dict)
  let assert Ok([first, ..]) =
    artifacts.parse(file_path_base("empty_base_params"))
  first.base_params |> should.equal(dict.new())

  let assert Ok([first, ..]) = artifacts.parse(file_path_base("empty_params"))
  first.params |> should.equal(dict.new())

  list.each(
    [
      #("empty_file", "Empty YAML file: " <> file_path_base("empty_file")),
      #("empty_artifacts", "artifacts is empty"),
      #("empty_name", "Expected name to be non-empty"),
      #("empty_version", "Expected version to be non-empty"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Missing ====
// * ✅ name
// * ✅ version
// * ✅ base_params
// * ✅ params
pub fn parse_missing_test() {
  list.each(
    [
      #("missing_name", "Missing name"),
      #("missing_version", "Missing version"),
      #("missing_base_params", "Missing base_params"),
      #("missing_params", "Missing params"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Duplicates ====
// * ✅ name (all artifacts must be unique)
// * ✅ base_params (all base_params must have unique labels)
// * ✅ params (all params must have unique labels)
pub fn parse_duplicates_test() {
  list.each(
    [
      #("duplicate_names", "Duplicate artifact names detected: datadog_sli"),
      #(
        "duplicate_base_params",
        "Duplicate keys detected for base_params: api_key",
      ),
      #("duplicate_params", "Duplicate keys detected for params: numerator"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Wrong Types ====
// * ✅ artifacts
// * ✅ name
// * ✅ version
// * ✅ base_params
//  * ✅ base_params is a map
//  * ✅ each base_param's value is an Accepted Type
// * ✅ params
//  * ✅ params is a map
//  * ✅ each param's value is an Accepted Type
pub fn parse_wrong_type_test() {
  list.each(
    [
      // wrong_type_artifacts is weird, but reasonable enough
      #("wrong_type_artifacts", "artifacts is empty"),
      #("wrong_type_name", "Expected name to be a string"),
      #("wrong_type_version", "Expected version to be a string"),
      #("wrong_type_base_params", "Expected base_params to be a map"),
      #("wrong_type_base_params_value", "Invalid type: NotARealType"),
      #("wrong_type_params", "Expected params to be a map"),
      #("wrong_type_params_value", "Invalid type: NotARealType"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}
