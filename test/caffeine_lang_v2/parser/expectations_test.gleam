import caffeine_lang_v2/parser/expectations.{ServiceExpectation}
import gleam/dict
import gleam/list
import gleeunit/should

// ==== Helpers ====
pub fn assert_error_on_parse(file_path, error_string) {
  expectations.parse(file_path_base(file_path))
  |> should.equal(Error(error_string))
}

pub fn file_path_base(file_path) {
  "test/caffeine_lang_v2/artifacts/parser_tests/expectations/"
  <> file_path
  <> ".yml"
}

// ==== Tests - Expectations ====
// ==== Happy Path ====
// * ✅ single
// * ✅ multiple
pub fn parse_test() {
  // single
  let expected_expectations = [
    ServiceExpectation(
      name: "Some operation succeeds in production",
      blueprint: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", "some_operation"),
        #("environment", "production"),
      ]),
    ),
  ]

  expectations.parse(file_path_base("happy_path_single"))
  |> should.equal(Ok(expected_expectations))

  // multiple
  let expected_expectations = [
    ServiceExpectation(
      name: "Some operation succeeds in production",
      blueprint: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", "some_operation"),
        #("environment", "production"),
      ]),
    ),
    ServiceExpectation(
      name: "Some other operation succeeds in production",
      blueprint: "success_rate_graphql",
      inputs: dict.from_list([
        #("gql_operation", "some_other_operation"),
        #("environment", "production"),
      ]),
    ),
  ]

  expectations.parse(file_path_base("happy_path_multiple"))
  |> should.equal(Ok(expected_expectations))
}

// ==== Empty ====
// * ✅ inputs - (empty dictionary)
// * ✅ expectations
// * ✅ name
// * ✅ blueprint
pub fn parse_empty_test() {
  // empty inputs is OK (treated as empty dict)
  let assert Ok([first, ..]) =
    expectations.parse(file_path_base("empty_inputs"))
  first.inputs |> should.equal(dict.new())

  list.each(
    [
      #("empty_expectations", "expectations is empty"),
      #("empty_name", "Expected name to be non-empty"),
      #("empty_blueprint", "Expected blueprint to be non-empty"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Missing ====
// * ✅ content (empty file)
// * ✅ expectations
// * ✅ name
// * ✅ blueprint
// * ✅ inputs
pub fn parse_missing_test() {
  list.each(
    [
      #("empty_file", "Empty YAML file: " <> file_path_base("empty_file")),
      #("empty_expectations", "expectations is empty"),
      #("missing_name", "Missing name"),
      #("missing_blueprint", "Missing blueprint"),
      #("missing_inputs", "Missing inputs"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Duplicates ====
// * ✅ name (all expectations must be unique)
// * ✅ inputs (all inputs must have unique labels)
pub fn parse_duplicates_test() {
  list.each(
    [
      #(
        "duplicate_names",
        "Duplicate expectation names detected: Some operation succeeds in production",
      ),
      #(
        "duplicate_inputs",
        "Duplicate keys detected for inputs: environment, gql_operation",
      ),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}

// ==== Wrong Types ====
// * ✅ expectations
// * ✅ name
// * ✅ blueprint
// * ✅ inputs (we will initially interpret all as String and later attempt to coalesce to the proper type)
pub fn parse_wrong_type_test() {
  list.each(
    [
      // wrong_type_expectations is weird, but reasonable enough
      #("wrong_type_expectations", "expectations is empty"),
      #("wrong_type_name", "Expected name to be a string"),
      #("wrong_type_blueprint", "Expected blueprint to be a string"),
      #("wrong_type_inputs", "Expected inputs to be a map"),
    ],
    fn(testcase) { assert_error_on_parse(testcase.0, testcase.1) },
  )
}
