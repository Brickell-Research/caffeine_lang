import caffeine_lang/common/accepted_types.{Float, PrimitiveType, String}
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/parser/artifacts.{type Artifact}
import caffeine_lang/parser/blueprints
import gleam/dict
import gleam/dynamic
import gleam/list
import gleeunit/should
import simplifile

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/blueprints/" <> file_name <> ".json"
}

fn artifacts() -> List(Artifact) {
  [
    artifacts.Artifact(
      name: "SLO",
      version: artifacts.Semver(0, 0, 1),
      inherited_params: dict.from_list([#("threshold", PrimitiveType(Float))]),
      required_params: dict.from_list([#("value", PrimitiveType(String))]),
    ),
  ]
}

fn assert_error(file_name: String, error: CompilationError) {
  blueprints.parse_from_json_file(path(file_name), artifacts())
  |> should.equal(Error(error))
}

// ==== Tests - Blueprints ====
// ==== Happy Path ====
// * ✅ none
// * ✅ single blueprint
// * ✅ multiple blueprints
pub fn parse_from_file_happy_path_test() {
  // none
  blueprints.parse_from_json_file(path("happy_path_none"), artifacts())
  |> should.equal(Ok([]))

  // single
  blueprints.parse_from_json_file(path("happy_path_single"), artifacts())
  |> should.equal(
    Ok([
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("percentile", PrimitiveType(Float)),
          #("threshold", PrimitiveType(Float)),
          #("value", PrimitiveType(String)),
        ]),
        inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
      ),
    ]),
  )

  // multiple
  blueprints.parse_from_json_file(path("happy_path_multiple"), artifacts())
  |> should.equal(
    Ok([
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("percentile", PrimitiveType(Float)),
          #("threshold", PrimitiveType(Float)),
          #("value", PrimitiveType(String)),
        ]),
        inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
      ),
      blueprints.Blueprint(
        name: "latency_p99",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #("value", PrimitiveType(String)),
        ]),
        inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
      ),
    ]),
  )
}

// ==== Missing ====
// * ✅ name
// * ✅ artifact_ref
// * ✅ params
// * ✅ inputs
pub fn parse_from_file_missing_test() {
  [
    #(
      "missing_name",
      "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.name)",
    ),
    #(
      "missing_artifact_ref",
      "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.artifact_ref)",
    ),
    #(
      "missing_params",
      "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.params)",
    ),
    #(
      "missing_inputs",
      "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.inputs)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}

// ==== Duplicates ====
// * ✅ name (all blueprints must be unique)
// * ✅ cannot overshadow inherited_params with params
pub fn parse_from_file_duplicates_test() {
  [
    #("duplicate_name", "Duplicate blueprint names: success_rate"),
    #(
      "duplicate_overshadowing_inherited_param",
      "Overshadowed inherited_params in blueprint error: Blueprint overshadowing inherited_params from artifact: threshold",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserDuplicateError(msg: pair.1))
  })
}

// ==== Wrong Types ====
// * ✅ blueprints
// * ✅ name
// * ✅ artifact_ref
// * ✅ params
//  * ✅ params is a map
//  * ✅ each param's value is an Accepted Type
// * ✅ inputs
//  * ✅ inputs is a map
//  * ✅ input value type validation
pub fn parse_from_file_wrong_type_test() {
  [
    #(
      "wrong_type_blueprints",
      "Incorrect types: expected (List) received (String) for (blueprints)",
    ),
    #(
      "wrong_type_name",
      "Incorrect types: expected (NonEmptyString) received (Int) for (blueprints.0.name)",
    ),
    #(
      "wrong_type_artifact_ref",
      "Incorrect types: expected (NamedReference) received (List) for (blueprints.0.artifact_ref)",
    ),
    #(
      "wrong_type_params_not_a_map",
      "Incorrect types: expected (Dict) received (List) for (blueprints.0.params)",
    ),
    #(
      "wrong_type_params_value_typo",
      "Incorrect types: expected (AcceptedType) received (String) for (blueprints.0.params.values)",
    ),
    #(
      "wrong_type_params_value_illegal",
      "Incorrect types: expected (AcceptedType) received (String) for (blueprints.0.params.values)",
    ),
    #(
      "wrong_type_inputs_not_a_map",
      "Incorrect types: expected (Dict) received (String) for (blueprints.0.inputs)",
    ),
    #(
      "wrong_type_input_value",
      "Input validation errors: expected (String) received (Int) for (value)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}

// ==== Semantic ====
// * ✅ blueprint references an actual artifact
pub fn parse_from_file_semantic_test() {
  [
    #(
      "semantic_artifact_ref",
      "Incorrect types: expected (NamedReference) received (String) for (blueprints.0.artifact_ref)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}

// ==== File Errors ====
// * ✅ file not found
pub fn parse_from_file_file_errors_test() {
  [
    #(
      "nonexistent_file_that_does_not_exist",
      simplifile.describe_error(simplifile.Enoent)
        <> " (test/caffeine_lang/corpus/parser/blueprints/nonexistent_file_that_does_not_exist.json)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserFileReadError(msg: pair.1))
  })
}

// ==== JSON Format Errors ====
// * ✅ invalid JSON syntax
// * ✅ empty file
// * ✅ null value
pub fn parse_from_file_json_format_test() {
  // These produce different error messages on Erlang vs JavaScript targets,
  // so we just check that they return a ParserJsonParserError
  ["json_invalid_syntax", "json_empty_file"]
  |> list.each(fn(file_name) {
    let result = blueprints.parse_from_json_file(path(file_name), artifacts())
    case result {
      Error(errors.ParserJsonParserError(msg: _)) -> should.be_true(True)
      _ -> should.fail()
    }
  })

  // This one has a consistent error message across targets
  assert_error(
    "json_null",
    errors.ParserJsonParserError(
      msg: "Incorrect types: expected (Dict) received (Nil) for (Unknown)",
    ),
  )
}

// ==== Edge Cases - Happy Path ====
// * ✅ empty params
pub fn parse_from_file_edge_cases_happy_path_test() {
  // empty params - should merge with artifact params
  blueprints.parse_from_json_file(path("happy_path_empty_params"), artifacts())
  |> should.equal(
    Ok([
      blueprints.Blueprint(
        name: "minimal_blueprint",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #("value", PrimitiveType(String)),
        ]),
        inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
      ),
    ]),
  )
}

// ==== Empty Name ====
// * ✅ empty string name is rejected
pub fn parse_from_file_empty_name_test() {
  [
    #(
      "empty_name",
      "Incorrect types: expected (NonEmptyString) received (String) for (blueprints.0.name)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}

// ==== Input Validation ====
// * ✅ missing required input
// * ✅ extra input field
pub fn parse_from_file_input_validation_test() {
  [
    #(
      "input_missing_required",
      "Input validation errors: Missing keys in input: value",
    ),
    #(
      "input_extra_field",
      "Input validation errors: Extra keys in input: extra",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}
