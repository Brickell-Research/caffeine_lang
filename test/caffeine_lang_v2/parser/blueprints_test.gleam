import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints
import gleam/dict
import gleam/dynamic
import gleam/list
import gleeunit/should

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang_v2/corpus/parser/blueprints/" <> file_name <> ".json"
}

fn artifacts() -> List(Artifact) {
  [
    artifacts.Artifact(
      name: "SLO",
      version: artifacts.Semver(0, 0, 1),
      base_params: dict.from_list([#("threshold", helpers.Float)]),
      params: dict.from_list([#("value", helpers.String)]),
    ),
  ]
}

fn assert_error(file_name: String, error: helpers.ParseError) {
  blueprints.parse_from_file(path(file_name), artifacts())
  |> should.equal(Error(error))
}

// ==== Tests - Blueprints ====
// ==== Happy Path ====
// * ✅ none
// * ✅ single blueprint
// * ✅ multiple blueprints
pub fn parse_from_file_happy_path_test() {
  // none
  blueprints.parse_from_file(path("happy_path_none"), artifacts())
  |> should.equal(Ok([]))

  // single
  blueprints.parse_from_file(path("happy_path_single"), artifacts())
  |> should.equal(
    Ok([
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("percentile", helpers.Float),
          #("threshold", helpers.Float),
        ]),
        inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
      ),
    ]),
  )

  // multiple
  blueprints.parse_from_file(path("happy_path_multiple"), artifacts())
  |> should.equal(
    Ok([
      blueprints.Blueprint(
        name: "success_rate",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("percentile", helpers.Float),
          #("threshold", helpers.Float),
        ]),
        inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
      ),
      blueprints.Blueprint(
        name: "latency_p99",
        artifact_ref: "SLO",
        params: dict.from_list([
          #("threshold", helpers.Float),
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
    assert_error(pair.0, helpers.JsonParserError(msg: pair.1))
  })
}

// ==== Duplicates ====
// * ✅ name (all blueprints must be unique)
// * ✅ cannot overshadow base_params with params
pub fn parse_from_file_duplicates_test() {
  [
    #("duplicate_name", "Duplicate blueprint names: success_rate"),
    #(
      "duplicate_overshadowing_base_param",
      "Overshadowed base_params in blueprint error: Blueprint overshadowing base_params from artifact: threshold",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, helpers.DuplicateError(msg: pair.1))
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
      "Incorrect types: expected (String) received (Int) for (blueprints.0.name)",
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
    assert_error(pair.0, helpers.JsonParserError(msg: pair.1))
  })
}

// ==== Semantic ====
// * ✅ artifact references an actual artifact
pub fn parse_from_file_semantic_test() {
  [
    #(
      "semantic_artifact_ref",
      "Incorrect types: expected (NamedReference) received (String) for (blueprints.0.artifact_ref)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, helpers.JsonParserError(msg: pair.1))
  })
}
