import caffeine_lang_v2/common/helpers.{Float, Integer, String}
import caffeine_lang_v2/parser/artifacts
import gleam/dict
import gleam/list
import gleam/result
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
// * ❌ none
// * ✅ single artifact
// * ✅ multiple artifacts
pub fn parse_test() {
  use artifact_1 <- result.try(artifacts.make_artifact(
    name: "slo",
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
  ))

  // single
  let expected_artifacts = [artifact_1]

  artifacts.parse(file_path_base("happy_path_single"))
  |> should.equal(Ok(expected_artifacts))

  // Note: Multiple different artifact types not tested since AcceptedArtifactNames
  // currently only has ServiceLevelObjective ("slo"). When more types are added,
  // happy_path_multiple.yml should be updated and this test expanded.

  // Required because `use` with result.try() makes this fn return Result
  Ok(Nil)
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
  // let assert Ok([first, ..]) =
  //   artifacts.parse(file_path_base("empty_base_params"))
  // artifacts.get_base_params(first) |> should.equal(dict.new())

  // let assert Ok([first, ..]) = artifacts.parse(file_path_base("empty_params"))
  // artifacts.get_params(first) |> should.equal(dict.new())

  list.each(
    [
      #("empty_base_params", "Expected base_params to be non-empty"),
      #("empty_params", "Expected params to be non-empty"),
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
      #("missing_name", "Missing name (failed at segment 0)"),
      #("missing_version", "Missing version (failed at segment 0)"),
      #("missing_base_params", "Missing base_params (failed at segment 0)"),
      #("missing_params", "Missing params (failed at segment 0)"),
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
      #("duplicate_names", "Duplicate artifact names detected: slo"),
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
      #("wrong_type_name", "Expected name to be a string, but found list"),
      #("wrong_type_version", "Expected version to be a string, but found list"),
      #(
        "wrong_type_base_params",
        "Expected base_params to be a map, but found string",
      ),
      #("wrong_type_base_params_value", "Invalid type: NotARealType"),
      #("wrong_type_params", "Expected params to be a map, but found string"),
      #("wrong_type_params_value", "Invalid type: NotARealType"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Semantic ====
// * ✅ version not semantic versioning
//   * ✅ no dots
//   * ✅ too many dots
//   * ✅ non numbers with two dots
//   * ✅ happy path
pub fn parse_semantic_test() {
  let name = "slo"
  let base_params = dict.new()
  let params = dict.new()

  artifacts.make_artifact(name, "0", base_params, params)
  |> should.equal(Error(
    "Version must follow semantic versioning (X.Y.Z). See: https://semver.org/. Received '0'.",
  ))

  artifacts.make_artifact(name, "0.0.0.0", base_params, params)
  |> should.equal(Error(
    "Version must follow semantic versioning (X.Y.Z). See: https://semver.org/. Received '0.0.0.0'.",
  ))

  artifacts.make_artifact(name, "A.0.0", base_params, params)
  |> should.equal(Error(
    "Version must follow semantic versioning (X.Y.Z). See: https://semver.org/. Received 'A.0.0'.",
  ))

  artifacts.make_artifact(name, "0.0.0", base_params, params)
  |> should.be_ok

  artifacts.make_artifact(name, "1.2.3", base_params, params)
  |> should.be_ok
}
