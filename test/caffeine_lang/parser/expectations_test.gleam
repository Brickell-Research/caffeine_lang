import caffeine_lang/common/accepted_types.{
  Defaulted, Float, ModifierType, PrimitiveType, String,
}
import caffeine_lang/common/constants
import caffeine_lang/common/errors
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations
import gleam/dict
import gleam/dynamic
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
      params: dict.from_list([#("percentile", PrimitiveType(Float))]),
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
        #("vendor", PrimitiveType(String)),
        #("threshold", PrimitiveType(Float)),
      ]),
      inputs: dict.from_list([
        #("vendor", dynamic.string(constants.vendor_datadog)),
      ]),
    ),
  ]
}

fn blueprints_with_defaulted() -> List(Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate_with_defaulted",
      artifact_ref: "SLO",
      params: dict.from_list([
        #("threshold", PrimitiveType(Float)),
        #("default_env", ModifierType(Defaulted(PrimitiveType(String), "production"))),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

// ==== Happy Path ====
// * ✅ empty expectations list
// * ✅ single expectation
// * ✅ multiple expectations
// * ✅ expectation with defaulted param in blueprint
pub fn parse_from_json_file_happy_path_test() {
  // empty expectations list
  expectations.parse_from_json_file(path("happy_path_none"), blueprints())
  |> should.equal(Ok([]))

  // single expectation - verify it parses and pairs with blueprint
  let assert Ok(result) =
    expectations.parse_from_json_file(path("happy_path_single"), blueprints())
  result
  |> should.equal([
    #(
      expectations.Expectation(
        name: "my_expectation",
        blueprint_ref: "success_rate",
        inputs: dict.from_list([#("percentile", dynamic.float(99.9))]),
      ),
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([#("percentile", PrimitiveType(Float))]),
        inputs: dict.from_list([]),
      ),
    ),
  ])

  // multiple expectations
  let assert Ok(result) =
    expectations.parse_from_json_file(path("happy_path_multiple"), blueprints())
  result
  |> should.equal([
    #(
      expectations.Expectation(
        name: "my_expectation",
        blueprint_ref: "success_rate",
        inputs: dict.from_list([#("percentile", dynamic.float(99.9))]),
      ),
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([#("percentile", PrimitiveType(Float))]),
        inputs: dict.from_list([]),
      ),
    ),
    #(
      expectations.Expectation(
        name: "another_expectation",
        blueprint_ref: "success_rate",
        inputs: dict.from_list([#("percentile", dynamic.float(95.0))]),
      ),
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([#("percentile", PrimitiveType(Float))]),
        inputs: dict.from_list([]),
      ),
    ),
  ])

  // expectation with defaulted param - input not provided is fine
  let assert Ok(result) =
    expectations.parse_from_json_file(
      path("happy_path_defaulted_param"),
      blueprints_with_defaulted(),
    )
  result
  |> should.equal([
    #(
      expectations.Expectation(
        name: "my_expectation_with_defaulted",
        blueprint_ref: "success_rate_with_defaulted",
        inputs: dict.from_list([#("threshold", dynamic.float(99.9))]),
      ),
      blueprints.Blueprint(
        name: "success_rate_with_defaulted",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #(
            "default_env",
            ModifierType(Defaulted(PrimitiveType(String), "production")),
          ),
        ]),
        inputs: dict.from_list([]),
      ),
    ),
  ])
}

// ==== Missing Fields ====
// * ✅ missing expectations field
// * ✅ missing name field
// * ✅ missing blueprint_ref field
// * ✅ missing inputs field
pub fn parse_from_json_file_missing_fields_test() {
  [
    #(
      "missing_expectations",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (expectations)",
      )),
    ),
    #(
      "missing_name",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (expectations.0.name)",
      )),
    ),
    #(
      "missing_blueprint_ref",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (expectations.0.blueprint_ref)",
      )),
    ),
    #(
      "missing_inputs",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (expectations.0.inputs)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== Wrong Types ====
// * ✅ expectations is not a list
// * ✅ name is not a string
// * ✅ blueprint_ref is not a string
// * ✅ inputs is not a map
// * ✅ input value has wrong type
pub fn parse_from_json_file_wrong_types_test() {
  [
    #(
      "wrong_type_expectations",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (List) received (String) for (expectations)",
      )),
    ),
    #(
      "wrong_type_name",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (Int) for (expectations.0.name)",
      )),
    ),
    #(
      "wrong_type_blueprint_ref",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NamedReference) received (List) for (expectations.0.blueprint_ref)",
      )),
    ),
    #(
      "wrong_type_inputs_not_a_map",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Dict) received (String) for (expectations.0.inputs)",
      )),
    ),
    #(
      "wrong_type_input_value",
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: expected (Float) received (String) for (percentile)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== Duplicates ====
// * ✅ duplicate expectation names within file
pub fn parse_from_json_file_duplicates_test() {
  [
    #(
      "duplicate_name",
      Error(errors.ParserDuplicateError(
        msg: "Duplicate expectation names: my_expectation",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== Empty Name ====
// * ✅ empty string name is rejected
pub fn parse_from_json_file_empty_name_test() {
  [
    #(
      "empty_name",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (String) for (expectations.0.name)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== Invalid Blueprint Reference ====
// * ✅ blueprint_ref references non-existent blueprint
pub fn parse_from_json_file_invalid_blueprint_ref_test() {
  [
    #(
      "semantic_blueprint_ref",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NamedReference) received (String) for (expectations.0.blueprint_ref)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== Input Overshadowing ====
// * ✅ expectation inputs cannot overshadow blueprint inputs
pub fn parse_from_json_file_overshadowing_test() {
  [
    #(
      "overshadowing_blueprint_input",
      Error(errors.ParserDuplicateError(
        msg: "Expectation 'my_expectation' overshadowing inputs from blueprint: vendor",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints_with_inputs())
  })
}

// ==== Input Validation ====
// * ✅ missing required input
// * ✅ extra input field not in params
pub fn parse_from_json_file_input_validation_test() {
  [
    #(
      "input_missing_required",
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: Missing keys in input: percentile",
      )),
    ),
    #(
      "input_extra_field",
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: Extra keys in input: extra",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== File Errors ====
// * ✅ file not found
pub fn parse_from_json_file_file_not_found_test() {
  [
    #(
      "nonexistent_file_that_does_not_exist",
      Error(errors.ParserFileReadError(
        msg: simplifile.describe_error(simplifile.Enoent)
          <> " (test/caffeine_lang/corpus/parser/expectations/nonexistent_file_that_does_not_exist.json)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}

// ==== JSON Format Errors ====
// * ✅ invalid JSON syntax
// * ✅ empty file
// * ✅ null value
pub fn parse_from_json_file_json_format_errors_test() {
  // These produce different error messages on Erlang vs JavaScript targets,
  // so we just check that they return a ParserJsonParserError
  [#("json_invalid_syntax", True), #("json_empty_file", True)]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    case expectations.parse_from_json_file(path(file_name), blueprints()) {
      Error(errors.ParserJsonParserError(msg: _)) -> True
      _ -> False
    }
  })

  // null value has consistent error message
  [
    #(
      "json_null",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Dict) received (Nil) for (Unknown)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    expectations.parse_from_json_file(path(file_name), blueprints())
  })
}
