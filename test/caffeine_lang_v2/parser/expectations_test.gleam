import caffeine_lang_v2/common/errors.{type ParseError}
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations
import gleam/dict
import gleam/dynamic
import gleam/list
import gleeunit/should

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang_v2/corpus/parser/expectations/" <> file_name <> ".json"
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

fn assert_error(file_name: String, error: ParseError) {
  expectations.parse_from_file(path(file_name), blueprints())
  |> should.equal(Error(error))
}

// ==== Tests - Expectations ====
// ==== Happy Path ====
// * ✅ none
// * ✅ single expectation
// * ✅ multiple expectations
pub fn parse_from_file_happy_path_test() {
  // none
  expectations.parse_from_file(path("happy_path_none"), blueprints())
  |> should.equal(Ok([]))

  expectations.parse_from_file(path("happy_path_single"), blueprints())
  |> should.equal(
    Ok([
      middle_end.IntermediateRepresentation(
        expectation_name: "parser_expectations_happy_path_single_my_expectation",
        artifact_ref: "SLO",
        values: [
          middle_end.ValueTuple(
            label: "percentile",
            typ: helpers.Float,
            value: dynamic.float(99.9),
          ),
        ],
      ),
    ]),
  )

  // multiple - names are prefixed with "parser_expectations_happy_path_multiple"
  expectations.parse_from_file(path("happy_path_multiple"), blueprints())
  |> should.equal(
    Ok([
      middle_end.IntermediateRepresentation(
        expectation_name: "parser_expectations_happy_path_multiple_my_expectation",
        artifact_ref: "SLO",
        values: [
          middle_end.ValueTuple(
            label: "percentile",
            typ: helpers.Float,
            value: dynamic.float(99.9),
          ),
        ],
      ),
      middle_end.IntermediateRepresentation(
        expectation_name: "parser_expectations_happy_path_multiple_another_expectation",
        artifact_ref: "SLO",
        values: [
          middle_end.ValueTuple(
            label: "percentile",
            typ: helpers.Float,
            value: dynamic.float(95.0),
          ),
        ],
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
      "Incorrect types: expected (String) received (Int) for (expectations.0.name)",
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
