import caffeine_lang_v2/common/errors.{type ParseError}
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts
import gleam/dict
import gleam/list
import gleeunit/should

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang_v2/corpus/parser/artifacts/" <> file_name <> ".json"
}

fn assert_error(file_name: String, error: ParseError) {
  artifacts.parse_from_file(path(file_name))
  |> should.equal(Error(error))
}

fn semver_0_0_1() {
  artifacts.Semver(0, 0, 1)
}

// ==== Tests - Artifacts ====
// ==== Happy Path ====
// * ✅ none
// * ✅ single artifact
// * ✅ multiple artifacts
pub fn parse_from_file_happy_path_test() {
  // none
  artifacts.parse_from_file(path("happy_path_none"))
  |> should.equal(Ok([]))

  // single
  artifacts.parse_from_file(path("happy_path_single"))
  |> should.equal(
    Ok([
      artifacts.Artifact(
        name: "SLO",
        version: semver_0_0_1(),
        base_params: dict.from_list([
          #("threshold", helpers.Float),
          #("window_in_days", helpers.Integer),
        ]),
        params: dict.from_list([
          #("queries", helpers.Dict(helpers.String, helpers.String)),
          #("value", helpers.String),
        ]),
      ),
    ]),
  )

  // multiple
  artifacts.parse_from_file(path("happy_path_multiple"))
  |> should.equal(
    Ok([
      artifacts.Artifact(
        name: "SLO",
        version: semver_0_0_1(),
        base_params: dict.from_list([
          #("threshold", helpers.Float),
          #("window_in_days", helpers.Integer),
        ]),
        params: dict.from_list([
          #("queries", helpers.Dict(helpers.String, helpers.String)),
          #("value", helpers.String),
        ]),
      ),
      artifacts.Artifact(
        name: "Dependency",
        version: semver_0_0_1(),
        base_params: dict.from_list([
          #("relationship", helpers.List(helpers.String)),
        ]),
        params: dict.from_list([
          #("isHard", helpers.Boolean),
        ]),
      ),
    ]),
  )
}

// ==== Missing ====
// * ✅ artifacts
// * ✅ name
// * ✅ version
// * ✅ base_params
// * ✅ params
// * ✅ multiple
pub fn parse_from_file_missing_test() {
  [
    #(
      "missing_artifacts",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts)",
    ),
    #(
      "missing_name",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.name)",
    ),
    #(
      "missing_version",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.version)",
    ),
    #(
      "missing_base_params",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.base_params)",
    ),
    #(
      "missing_params",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.params)",
    ),
    #(
      "missing_multiple",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.version), expected (Field) received (Nothing) for (artifacts.0.base_params), expected (Field) received (Nothing) for (artifacts.0.params)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Duplicates ====
// * ✅ name (all artifacts must be unique)
pub fn parse_from_file_duplicates_test() {
  [
    #("duplicate_names", "Duplicate artifact names: SLO"),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.DuplicateError(msg: pair.1))
  })
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
// * ✅ multiple
pub fn parse_from_file_wrong_type_test() {
  [
    #(
      "wrong_type_artifacts",
      "Incorrect types: expected (List) received (String) for (artifacts)",
    ),
    #(
      "wrong_type_name",
      "Incorrect types: expected (String) received (Int) for (artifacts.0.name)",
    ),
    #(
      "wrong_type_version",
      "Incorrect types: expected (Semver) received (List) for (artifacts.0.version)",
    ),
    #(
      "wrong_type_base_params_not_map",
      "Incorrect types: expected (Dict) received (Float) for (artifacts.1.base_params)",
    ),
    #(
      "wrong_type_base_params_value_not_accepted_type_made_up",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.base_params.values)",
    ),
    #(
      "wrong_type_base_params_value_not_accepted_type_typo",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.base_params.values)",
    ),
    #(
      "wrong_type_params_not_map",
      "Incorrect types: expected (Dict) received (String) for (artifacts.0.params)",
    ),
    #(
      "wrong_type_params_value_not_accepted_type_illegal",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
    ),
    #(
      "wrong_type_multiple",
      "Incorrect types: expected (String) received (Int) for (artifacts.0.name), expected (Semver) received (Int) for (artifacts.0.version), expected (AcceptedType) received (String) for (artifacts.0.params.values)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}

// ==== Semantic ====
// * ✅ version not semantic versioning
//   * ✅ no dots
//   * ✅ too many dots
//   * ✅ non numbers with two dots
pub fn parse_from_file_semver_test() {
  [
    #(
      "semver_no_dots",
      "Incorrect types: expected (Semver) received (String) for (artifacts.0.version)",
    ),
    #(
      "semver_too_many_dots",
      "Incorrect types: expected (Semver) received (String) for (artifacts.0.version)",
    ),
    #(
      "semver_non_numbers",
      "Incorrect types: expected (Semver) received (String) for (artifacts.0.version)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.JsonParserError(msg: pair.1))
  })
}
