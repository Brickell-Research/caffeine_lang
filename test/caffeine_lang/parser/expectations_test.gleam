import caffeine_lang/common/errors.{type ParseError}
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
import gleeunit/should
import simplifile
import test_helpers

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/expectations/" <> file_name <> ".json"
}

fn blueprints() -> List(Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate",
      artifact_ref: "SLO",
      params: dict.from_list([#("percentile", helpers.Float)]),
      inputs: dict.from_list([]),
    ),
  ]
}

fn blueprints_with_inputs() -> List(Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate_with_defaults",
      artifact_ref: "SLO",
      params: dict.from_list([
        #("vendor", helpers.String),
        #("threshold", helpers.Float),
      ]),
      inputs: dict.from_list([#("vendor", dynamic.string("datadog"))]),
    ),
  ]
}

fn blueprints_with_defaulted() -> List(Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate_with_defaulted",
      artifact_ref: "SLO",
      params: dict.from_list([
        #("threshold", helpers.Float),
        #("default_env", helpers.Defaulted(helpers.String, "production")),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

fn assert_error(file_name: String, error: ParseError) {
  expectations.parse_from_file(path(file_name), blueprints())
  |> should.equal(Error(error))
}

// ==== Tests - Expectations ====
// ==== Happy Path ====
// * ✅ none
// * ✅ single expectation
// * ✅ multiple expectations
// * ✅ defaulted param not provided (should include in value_tuples with nil)
pub fn parse_from_file_happy_path_test() {
  // none
  expectations.parse_from_file(path("happy_path_none"), blueprints())
  |> should.equal(Ok([]))

  expectations.parse_from_file(path("happy_path_single"), blueprints())
  |> should.equal(
    Ok([
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "my_expectation",
          org_name: "parser",
          service_name: "happy_path_single",
          blueprint_name: "success_rate",
          team_name: "expectations",
        ),
        unique_identifier: "parser_happy_path_single_my_expectation",
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            label: "percentile",
            typ: helpers.Float,
            value: dynamic.float(99.9),
          ),
        ],
        vendor: option.None,
      ),
    ]),
  )

  // multiple - names are prefixed with "parser_happy_path_multiple"
  expectations.parse_from_file(path("happy_path_multiple"), blueprints())
  |> should.equal(
    Ok([
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "my_expectation",
          org_name: "parser",
          service_name: "happy_path_multiple",
          blueprint_name: "success_rate",
          team_name: "expectations",
        ),
        unique_identifier: "parser_happy_path_multiple_my_expectation",
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            label: "percentile",
            typ: helpers.Float,
            value: dynamic.float(99.9),
          ),
        ],
        vendor: option.None,
      ),
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "another_expectation",
          org_name: "parser",
          service_name: "happy_path_multiple",
          blueprint_name: "success_rate",
          team_name: "expectations",
        ),
        unique_identifier: "parser_happy_path_multiple_another_expectation",
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            label: "percentile",
            typ: helpers.Float,
            value: dynamic.float(95.0),
          ),
        ],
        vendor: option.None,
      ),
    ]),
  )

  // defaulted param not provided - should still create value tuple with nil
  expectations.parse_from_file(
    path("happy_path_defaulted_param"),
    blueprints_with_defaulted(),
  )
  |> should.equal(
    Ok([
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "my_expectation_with_defaulted",
          org_name: "parser",
          service_name: "happy_path_defaulted_param",
          blueprint_name: "success_rate_with_defaulted",
          team_name: "expectations",
        ),
        unique_identifier: "parser_happy_path_defaulted_param_my_expectation_with_defaulted",
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            label: "threshold",
            typ: helpers.Float,
            value: dynamic.float(99.9),
          ),
          helpers.ValueTuple(
            label: "default_env",
            typ: helpers.Defaulted(helpers.String, "production"),
            value: dynamic.nil(),
          ),
        ],
        vendor: option.None,
      ),
    ]),
  )
}

// ==== Missing ====
// * ✅ expectations
// * ✅ name
// * ✅ blueprint_ref
// * ✅ inputs
pub fn parse_from_file_missing_test() {
  [
    #(
      "missing_expectations",
      "Incorrect types: expected (Field) received (Nothing) for (expectations)",
    ),
    #(
      "missing_name",
      "Incorrect types: expected (Field) received (Nothing) for (expectations.0.name)",
    ),
    #(
      "missing_blueprint_ref",
      "Incorrect types: expected (Field) received (Nothing) for (expectations.0.blueprint_ref)",
    ),
    #(
      "missing_inputs",
      "Incorrect types: expected (Field) received (Nothing) for (expectations.0.inputs)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Duplicates ====
// * ✅ name (all expectations must be unique)
pub fn parse_from_file_duplicates_test() {
  [#("duplicate_name", "Duplicate expectation names: my_expectation")]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.DuplicateError(msg: pair.1))
  })
}

// ==== Wrong Types ====
// * ✅ expectations
// * ✅ name
// * ✅ blueprint_ref
// * ✅ inputs
//   * ✅ inputs is not a map
//   * ✅ input value type validation
pub fn parse_from_file_wrong_type_test() {
  [
    #(
      "wrong_type_expectations",
      "Incorrect types: expected (List) received (String) for (expectations)",
    ),
    #(
      "wrong_type_name",
      "Incorrect types: expected (NonEmptyString) received (Int) for (expectations.0.name)",
    ),
    #(
      "wrong_type_blueprint_ref",
      "Incorrect types: expected (NamedReference) received (List) for (expectations.0.blueprint_ref)",
    ),
    #(
      "wrong_type_inputs_not_a_map",
      "Incorrect types: expected (Dict) received (String) for (expectations.0.inputs)",
    ),
    #(
      "wrong_type_input_value",
      "Input validation errors: expected (Float) received (String) for (percentile)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Semantic ====
// * ✅ blueprint_ref references an actual blueprint
pub fn parse_from_file_semantic_test() {
  [
    #(
      "semantic_blueprint_ref",
      "Incorrect types: expected (NamedReference) received (String) for (expectations.0.blueprint_ref)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Overshadowing ====
// * ✅ expectation inputs cannot overshadow blueprint inputs
pub fn parse_from_file_overshadowing_test() {
  expectations.parse_from_file(
    path("overshadowing_blueprint_input"),
    blueprints_with_inputs(),
  )
  |> should.equal(
    Error(errors.DuplicateError(
      msg: "Expectation 'my_expectation' overshadowing inputs from blueprint: vendor",
    )),
  )
}

// ==== Extract Path Prefix ====
// ✅ happy path
// ✅ sad path - however unlikely
pub fn extract_path_prefix_test() {
  [
    #("org/team/service.json", #("org", "team", "service")),
    #("org/team", #("unknown", "unknown", "unknown")),
  ]
  |> test_helpers.array_based_test_executor_1(expectations.extract_path_prefix)
}

// ==== File Errors ====
// * ✅ file not found
pub fn parse_from_file_file_errors_test() {
  [
    #(
      "nonexistent_file_that_does_not_exist",
      simplifile.describe_error(simplifile.Enoent)
        <> " (test/caffeine_lang/corpus/parser/expectations/nonexistent_file_that_does_not_exist.json)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.FileReadError(msg: pair.1))
  })
}

// ==== JSON Format Errors ====
// * ✅ invalid JSON syntax
// * ✅ empty file
// * ✅ null value
pub fn parse_from_file_json_format_test() {
  [
    #("json_invalid_syntax", "Unexpected end of input."),
    #("json_empty_file", "Unexpected end of input."),
    #(
      "json_null",
      "Incorrect types: expected (Dict) received (Nil) for (Unknown)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Empty Name ====
// * ✅ empty string name is rejected
pub fn parse_from_file_empty_name_test() {
  [
    #(
      "empty_name",
      "Incorrect types: expected (NonEmptyString) received (String) for (expectations.0.name)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Input Validation ====
// * ✅ missing required input
// * ✅ extra input field
pub fn parse_from_file_input_validation_test() {
  [
    #(
      "input_missing_required",
      "Input validation errors: Missing keys in input: percentile",
    ),
    #(
      "input_extra_field",
      "Input validation errors: Extra keys in input: extra",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}
