import caffeine_lang/common/accepted_types
import caffeine_lang/common/constants
import caffeine_lang/common/errors
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations
import gleam/dict
import gleam/dynamic
import simplifile
import test_helpers

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/expectations/" <> file_name <> ".json"
}

fn parse_from_file(file_path: String, blueprints: List(Blueprint)) {
  let assert Ok(json) = simplifile.read(file_path)
  expectations.parse_from_json_string(json, blueprints, source_path: file_path)
}

fn blueprints() -> List(Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate",
      artifact_refs: ["SLO"],
      params: dict.from_list([
        #(
          "percentile",
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
        ),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

fn blueprints_with_inputs() -> List(Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate_with_defaults",
      artifact_refs: ["SLO"],
      params: dict.from_list([
        #("vendor", accepted_types.PrimitiveType(primitive_types.String)),
        #(
          "threshold",
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
        ),
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
      artifact_refs: ["SLO"],
      params: dict.from_list([
        #(
          "threshold",
          accepted_types.PrimitiveType(primitive_types.NumericType(
            numeric_types.Float,
          )),
        ),
        #(
          "default_env",
          accepted_types.ModifierType(modifier_types.Defaulted(
            accepted_types.PrimitiveType(primitive_types.String),
            "production",
          )),
        ),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

// ==== parse_from_json_string ====
// * ✅ happy path - empty expectations list
// * ✅ happy path - single expectation
// * ✅ happy path - multiple expectations
// * ✅ happy path - expectation with defaulted param in blueprint
// * ✅ missing - expectations field
// * ✅ missing - name field
// * ✅ missing - blueprint_ref field
// * ✅ missing - inputs field
// * ✅ wrong type - expectations is not a list
// * ✅ wrong type - name is not a string
// * ✅ wrong type - blueprint_ref is not a string
// * ✅ wrong type - inputs is not a map
// * ✅ wrong type - input value has wrong type
// * ✅ duplicates - duplicate expectation names within file
// * ✅ empty name - empty string name is rejected
// * ✅ invalid blueprint ref - blueprint_ref references non-existent blueprint
// * ✅ overshadowing - expectation inputs cannot overshadow blueprint inputs
// * ✅ input validation - missing required input
// * ✅ input validation - extra input field not in params
// * ✅ file error - file not found
// * ✅ json format - invalid JSON syntax
// * ✅ json format - empty file
// * ✅ json format - null value
pub fn parse_from_json_string_test() {
  // Happy paths
  [#(path("happy_path_none"), Ok([]))]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, blueprints())
  })

  // single expectation - verify it parses and pairs with blueprint
  [
    #(
      path("happy_path_single"),
      Ok([
        #(
          expectations.Expectation(
            name: "my_expectation",
            blueprint_ref: "success_rate",
            inputs: dict.from_list([#("percentile", dynamic.float(99.9))]),
          ),
          blueprints.Blueprint(
            name: "success_rate",
            artifact_refs: ["SLO"],
            params: dict.from_list([
              #(
                "percentile",
                accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Float,
                )),
              ),
            ]),
            inputs: dict.from_list([]),
          ),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, blueprints())
  })

  // multiple expectations
  [
    #(
      path("happy_path_multiple"),
      Ok([
        #(
          expectations.Expectation(
            name: "my_expectation",
            blueprint_ref: "success_rate",
            inputs: dict.from_list([#("percentile", dynamic.float(99.9))]),
          ),
          blueprints.Blueprint(
            name: "success_rate",
            artifact_refs: ["SLO"],
            params: dict.from_list([
              #(
                "percentile",
                accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Float,
                )),
              ),
            ]),
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
            artifact_refs: ["SLO"],
            params: dict.from_list([
              #(
                "percentile",
                accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Float,
                )),
              ),
            ]),
            inputs: dict.from_list([]),
          ),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, blueprints())
  })

  // expectation with defaulted param - input not provided is fine
  [
    #(
      path("happy_path_defaulted_param"),
      Ok([
        #(
          expectations.Expectation(
            name: "my_expectation_with_defaulted",
            blueprint_ref: "success_rate_with_defaulted",
            inputs: dict.from_list([#("threshold", dynamic.float(99.9))]),
          ),
          blueprints.Blueprint(
            name: "success_rate_with_defaulted",
            artifact_refs: ["SLO"],
            params: dict.from_list([
              #(
                "threshold",
                accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Float,
                )),
              ),
              #(
                "default_env",
                accepted_types.ModifierType(modifier_types.Defaulted(
                  accepted_types.PrimitiveType(primitive_types.String),
                  "production",
                )),
              ),
            ]),
            inputs: dict.from_list([]),
          ),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, blueprints_with_defaulted())
  })

  // Missing fields
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
    parse_from_file(path(file_name), blueprints())
  })

  // Wrong types
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
        msg: "Input validation errors: expectation 'parser.expectations.wrong_type_input_value.my_expectation' - expected (Float) received (String) for (percentile)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    parse_from_file(path(file_name), blueprints())
  })

  // Duplicates
  [
    #(
      "duplicate_name",
      Error(errors.ParserDuplicateError(
        msg: "Duplicate expectation names: my_expectation",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    parse_from_file(path(file_name), blueprints())
  })

  // Empty name
  [
    #(
      "empty_name",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (String) for (expectations.0.name)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    parse_from_file(path(file_name), blueprints())
  })

  // Invalid blueprint reference
  [
    #(
      "semantic_blueprint_ref",
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NamedReference) received (String) for (expectations.0.blueprint_ref)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    parse_from_file(path(file_name), blueprints())
  })

  // Overshadowing
  [
    #(
      "overshadowing_blueprint_input",
      Error(errors.ParserDuplicateError(
        msg: "expectation 'parser.expectations.overshadowing_blueprint_input.my_expectation' - overshadowing inputs from blueprint: vendor",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    parse_from_file(path(file_name), blueprints_with_inputs())
  })

  // Input validation
  [
    #(
      "input_missing_required",
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: expectation 'parser.expectations.input_missing_required.my_expectation' - Missing keys in input: percentile",
      )),
    ),
    #(
      "input_extra_field",
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: expectation 'parser.expectations.input_extra_field.my_expectation' - Extra keys in input: extra",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    parse_from_file(path(file_name), blueprints())
  })

  // JSON format errors - different error messages on Erlang vs JavaScript targets
  [#("json_invalid_syntax", True), #("json_empty_file", True)]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    case parse_from_file(path(file_name), blueprints()) {
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
    parse_from_file(path(file_name), blueprints())
  })
}
