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
  artifacts.parse_from_json_file(path(file_name))
  |> should.equal(Error(error))
}

// ==== Tests - Artifacts ====
// ==== Happy Path ====
// * ✅ none
// * ✅ single artifact
// * ✅ multiple artifacts
pub fn parse_from_file_happy_path_test() {
  // none
  artifacts.parse_from_json_file(path("happy_path_none"))
  |> should.equal(Ok([]))

  // single
  artifacts.parse_from_json_file(path("happy_path_single"))
  |> should.equal(
    Ok([
      artifacts.Artifact(
        name: "SLO",
        params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #("window_in_days", PrimitiveType(Integer)),
          #(
            "queries",
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
          ),
          #("value", PrimitiveType(String)),
        ]),
      ),
    ]),
  )

  // multiple
  artifacts.parse_from_json_file(path("happy_path_multiple"))
  |> should.equal(
    Ok([
      artifacts.Artifact(
        name: "SLO",
        params: dict.from_list([
          #("threshold", PrimitiveType(Float)),
          #("window_in_days", PrimitiveType(Integer)),
          #(
            "queries",
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
          ),
          #("value", PrimitiveType(String)),
        ]),
      ),
      artifacts.Artifact(
        name: "Dependency",
        params: dict.from_list([
          #("relationship", CollectionType(List(PrimitiveType(String)))),
          #("isHard", PrimitiveType(Boolean)),
        ]),
      ),
    ]),
  )
}

// ==== Missing ====
// * ✅ artifacts
// * ✅ name
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
      "missing_params",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.params)",
    ),
    #(
      "missing_multiple",
      "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.name), expected (Field) received (Nothing) for (artifacts.0.params)",
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
// * ✅ params
//   * ✅ params is a map
//   * ✅ each param's value is an Accepted Type (made up, typo, illegal nesting)
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
      "wrong_type_params_not_map",
      "Incorrect types: expected (Dict) received (Float) for (artifacts.1.params)",
    ),
    #(
      "wrong_type_params_value_not_accepted_type_made_up",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
    ),
    #(
      "wrong_type_params_value_not_accepted_type_typo",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
    ),
    #(
      "wrong_type_params_value_not_accepted_type_illegal",
      "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
    ),
    #(
      "wrong_type_multiple",
      "Incorrect types: expected (NonEmptyString) received (Int) for (artifacts.0.name), expected (AcceptedType) received (String) for (artifacts.0.params.values)",
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
    let result = artifacts.parse_from_json_file(path(file_name))
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
  // empty params
  artifacts.parse_from_json_file(path("happy_path_empty_params"))
  |> should.equal(
    Ok([
      artifacts.Artifact(name: "MinimalArtifact", params: dict.new()),
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
