import caffeine_lang/common/accepted_types.{
  Boolean, CollectionType, Dict, Float, Integer, List, PrimitiveType, String,
}
import caffeine_lang/common/errors
import caffeine_lang/parser/artifacts
import gleam/dict
import test_helpers

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/artifacts/" <> file_name <> ".json"
}

// ==== parse_from_json_file ====
// * ✅ happy path - none
// * ✅ happy path - single artifact
// * ✅ happy path - multiple artifacts
// * ✅ happy path - empty params
// * ✅ missing - artifacts
// * ✅ missing - name
// * ✅ missing - params
// * ✅ missing - multiple
// * ✅ duplicates - name (all artifacts must be unique)
// * ✅ wrong type - artifacts
// * ✅ wrong type - name
// * ✅ wrong type - params is a map
// * ✅ wrong type - each param's value is an Accepted Type (made up, typo, illegal nesting)
// * ✅ wrong type - multiple
// * ✅ file error - file not found
// * ✅ json format - invalid JSON syntax
// * ✅ json format - empty file
// * ✅ json format - null value
// * ✅ empty name - empty string name is rejected
pub fn parse_from_json_file_test() {
  // Happy paths
  [
    // none
    #(path("happy_path_none"), Ok([])),
    // single
    #(
      path("happy_path_single"),
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
    ),
    // multiple
    #(
      path("happy_path_multiple"),
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
    ),
    // empty params
    #(
      path("happy_path_empty_params"),
      Ok([artifacts.Artifact(name: "MinimalArtifact", params: dict.new())]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)

  // Missing fields
  [
    #(
      path("missing_artifacts"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (artifacts)",
      )),
    ),
    #(
      path("missing_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.name)",
      )),
    ),
    #(
      path("missing_params"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.params)",
      )),
    ),
    #(
      path("missing_multiple"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.name), expected (Field) received (Nothing) for (artifacts.0.params)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)

  // Duplicates
  [
    #(
      path("duplicate_names"),
      Error(errors.ParserDuplicateError(msg: "Duplicate artifact names: SLO")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)

  // Wrong types
  [
    #(
      path("wrong_type_artifacts"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (List) received (String) for (artifacts)",
      )),
    ),
    #(
      path("wrong_type_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (Int) for (artifacts.0.name)",
      )),
    ),
    #(
      path("wrong_type_params_not_map"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Dict) received (Float) for (artifacts.1.params)",
      )),
    ),
    #(
      path("wrong_type_params_value_not_accepted_type_made_up"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
      )),
    ),
    #(
      path("wrong_type_params_value_not_accepted_type_typo"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
      )),
    ),
    #(
      path("wrong_type_params_value_not_accepted_type_illegal"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType) received (String) for (artifacts.0.params.values)",
      )),
    ),
    #(
      path("wrong_type_multiple"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (Int) for (artifacts.0.name), expected (AcceptedType) received (String) for (artifacts.0.params.values)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)

  // File errors
  [
    #(
      path("nonexistent_file_that_does_not_exist"),
      Error(errors.ParserFileReadError(
        msg: "No such file or directory (test/caffeine_lang/corpus/parser/artifacts/nonexistent_file_that_does_not_exist.json)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)

  // JSON format errors - different error messages on Erlang vs JavaScript targets
  [#("json_invalid_syntax", True), #("json_empty_file", True)]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    case artifacts.parse_from_json_file(path(file_name)) {
      Error(errors.ParserJsonParserError(msg: _)) -> True
      _ -> False
    }
  })

  // null value has consistent error message
  [
    #(
      path("json_null"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Dict) received (Nil) for (Unknown)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)

  // Empty name
  [
    #(
      path("empty_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (String) for (artifacts.0.name)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(artifacts.parse_from_json_file)
}

// ==== parse_standard_library ====
// * ✅ parses without error
pub fn parse_standard_library_test() {
  [#(Nil, True)]
  |> test_helpers.array_based_test_executor_1(fn(_) {
    case artifacts.parse_standard_library() {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}
