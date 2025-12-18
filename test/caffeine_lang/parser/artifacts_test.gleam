import caffeine_lang/common/accepted_types.{
  Boolean, CollectionType, Dict, Float, Integer, List, PrimitiveType, String,
}
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/parser/artifacts
import gleam/dict
import gleam/list
import gleeunit/should
import simplifile

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/artifacts/" <> file_name <> ".json"
}

fn assert_error(file_name: String, error: CompilationError) {
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
        inherited_params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #("window_in_days", PrimitiveType(Integer)),
        ]),
        required_params: dict.from_list([
          #("queries", CollectionType(Dict(PrimitiveType(String), PrimitiveType(String)))),
          #("value", PrimitiveType(String)),
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
        inherited_params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #("window_in_days", PrimitiveType(Integer)),
        ]),
        required_params: dict.from_list([
          #("queries", CollectionType(Dict(PrimitiveType(String), PrimitiveType(String)))),
          #("value", PrimitiveType(String)),
        ]),
      ),
      artifacts.Artifact(
        name: "Dependency",
        version: semver_0_0_1(),
        inherited_params: dict.from_list([
          #("relationship", CollectionType(List(PrimitiveType(String)))),
        ]),
        required_params: dict.from_list([
          #("isHard", PrimitiveType(Boolean)),
        ]),
      ),
    ]),
  )
}

// ==== Missing ====
// * ✅ artifacts
// * ✅ name
// * ✅ version
// * ✅ inherited_params
// * ✅ required_params
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
      "missing_inherited_params",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.inherited_params)",
    ),
    #(
      "missing_required_params",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.required_params)",
    ),
    #(
      "missing_multiple",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.version), expected (Field) received (Nothing) for (artifacts.0.inherited_params), expected (Field) received (Nothing) for (artifacts.0.required_params)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}

// ==== Duplicates ====
// * ✅ name (all artifacts must be unique)
pub fn parse_from_file_duplicates_test() {
  [
    #("duplicate_names", "Duplicate artifact names: SLO"),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserDuplicateError(msg: pair.1))
  })
}

// ==== Wrong Types ====
// * ✅ artifacts
// * ✅ name
// * ✅ version
// * ✅ inherited_params
//  * ✅ inherited_params is a map
//  * ✅ each inherited_param's value is an Accepted Type
// * ✅ required_params
//  * ✅ required_params is a map
//  * ✅ each required_param's value is an Accepted Type
// * ✅ multiple
pub fn parse_from_file_wrong_type_test() {
  [
    #(
      "wrong_type_artifacts",
      "Incorrect types: expected (List) received (String) for (artifacts)",
    ),
    #(
      "wrong_type_name",
      "Incorrect types: expected (NonEmptyString) received (Int) for (artifacts.0.name)",
    ),
    #(
      "wrong_type_version",
      "Incorrect types: expected (Semver) received (List) for (artifacts.0.version)",
    ),
    #(
      "wrong_type_inherited_params_not_map",
      "Incorrect types: expected (Dict) received (Float) for (artifacts.1.inherited_params)",
    ),
    #(
      "wrong_type_inherited_params_value_not_accepted_type_made_up",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.inherited_params.values)",
    ),
    #(
      "wrong_type_inherited_params_value_not_accepted_type_typo",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.inherited_params.values)",
    ),
    #(
      "wrong_type_required_params_not_map",
      "Incorrect types: expected (Dict) received (String) for (artifacts.0.required_params)",
    ),
    #(
      "wrong_type_required_params_value_not_accepted_type_illegal",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.required_params.values)",
    ),
    #(
      "wrong_type_multiple",
      "Incorrect types: expected (NonEmptyString) received (Int) for (artifacts.0.name), expected (Semver) received (Int) for (artifacts.0.version), expected (AcceptedType) received (String) for (artifacts.0.required_params.values)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
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
        <> " (test/caffeine_lang/corpus/parser/artifacts/nonexistent_file_that_does_not_exist.json)",
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
    let result = artifacts.parse_from_file(path(file_name))
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
// * ✅ empty inherited_params and required_params
// * ✅ version 0.0.0
pub fn parse_from_file_edge_cases_happy_path_test() {
  // empty params
  artifacts.parse_from_file(path("happy_path_empty_params"))
  |> should.equal(
    Ok([
      artifacts.Artifact(
        name: "MinimalArtifact",
        version: artifacts.Semver(0, 0, 1),
        inherited_params: dict.new(),
        required_params: dict.new(),
      ),
    ]),
  )

  // version 0.0.0
  artifacts.parse_from_file(path("happy_path_version_zero"))
  |> should.equal(
    Ok([
      artifacts.Artifact(
        name: "ZeroVersion",
        version: artifacts.Semver(0, 0, 0),
        inherited_params: dict.new(),
        required_params: dict.new(),
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
      "Incorrect types: expected (NonEmptyString) received (String) for (artifacts.0.name)",
    ),
  ]
  |> list.each(fn(pair) {
    assert_error(pair.0, errors.ParserJsonParserError(msg: pair.1))
  })
}

// ==== Standard Library ====
// * ✅ parses without error
pub fn parse_standard_library_test() {
  artifacts.parse_standard_library()
  |> should.be_ok
}

// ==== parse_semver ====
// ==== Happy Path ====
// * ✅ standard semver (1.2.3)
// * ✅ zero version (0.0.0)
// * ✅ large numbers
pub fn parse_semver_happy_path_test() {
  [
    #("1.2.3", Ok(artifacts.Semver(1, 2, 3))),
    #("0.0.0", Ok(artifacts.Semver(0, 0, 0))),
    #("999.999.999", Ok(artifacts.Semver(999, 999, 999))),
  ]
  |> list.each(fn(pair) {
    artifacts.parse_semver(pair.0)
    |> should.equal(pair.1)
  })
}

// ==== Invalid ====
// * ✅ wrong number of parts (no dots, one dot, too many dots)
// * ✅ non-numeric parts
// * ✅ empty/whitespace
// * ✅ malformed dots (leading, trailing, consecutive)
// * ✅ semver extensions (prerelease, build metadata)
// * ✅ leading zeros
// * ✅ negative numbers
pub fn parse_semver_invalid_test() {
  [
    // Wrong number of parts
    #("1", Error(Nil)),
    #("1.2", Error(Nil)),
    #("1.2.3.4", Error(Nil)),
    // Non-numeric
    #("a.b.c", Error(Nil)),
    #("1.2.a", Error(Nil)),
    #("v1.2.3", Error(Nil)),
    // Empty/whitespace
    #("", Error(Nil)),
    #("   ", Error(Nil)),
    // Malformed dots
    #(".1.2.3", Error(Nil)),
    #("1.2.3.", Error(Nil)),
    #("1..3", Error(Nil)),
    #("1.2.", Error(Nil)),
    #("..", Error(Nil)),
    // Semver extensions not supported
    #("1.2.3-beta", Error(Nil)),
    #("1.2.3+build", Error(Nil)),
    // Leading zeros disallowed
    #("01.2.3", Error(Nil)),
    #("1.02.3", Error(Nil)),
    #("1.2.03", Error(Nil)),
    #("01.02.03", Error(Nil)),
    // Negative numbers disallowed
    #("-1.0.2", Error(Nil)),
    #("0.-1.0", Error(Nil)),
    #("0.0.-1", Error(Nil)),
  ]
  |> list.each(fn(pair) {
    artifacts.parse_semver(pair.0)
    |> should.equal(pair.1)
  })
}
