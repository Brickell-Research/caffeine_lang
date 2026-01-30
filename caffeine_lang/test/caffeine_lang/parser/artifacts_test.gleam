import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/errors
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/parser/artifacts.{ParamInfo}
import gleam/dict
import gleam/string
import simplifile
import test_helpers

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/artifacts/" <> file_name <> ".json"
}

fn parse_from_file(file_path: String) {
  let assert Ok(json) = simplifile.read(file_path)
  artifacts.parse_from_json_string(json)
}

// ==== parse_from_json_string ====
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
// * ✅ json format - invalid JSON syntax
// * ✅ json format - empty file
// * ✅ json format - null value
// * ✅ empty name - empty string name is rejected
pub fn parse_from_json_string_test() {
  // Happy paths
  [
    // none
    #(path("happy_path_none"), Ok([])),
    // single
    #(
      path("happy_path_single"),
      Ok([
        artifacts.Artifact(
          type_: artifacts.SLO,
          description: "A test SLO artifact",
          params: dict.from_list([
            #(
              "threshold",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Float,
                )),
                description: "The threshold value",
              ),
            ),
            #(
              "window_in_days",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Integer,
                )),
                description: "Window period in days",
              ),
            ),
            #(
              "queries",
              ParamInfo(
                type_: accepted_types.CollectionType(collection_types.Dict(
                  accepted_types.PrimitiveType(primitive_types.String),
                  accepted_types.PrimitiveType(primitive_types.String),
                )),
                description: "Metric queries",
              ),
            ),
            #(
              "value",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.String),
                description: "The SLO value",
              ),
            ),
          ]),
        ),
      ]),
    ),
    // multiple
    #(
      path("happy_path_multiple"),
      Ok([
        artifacts.Artifact(
          type_: artifacts.SLO,
          description: "A test SLO artifact",
          params: dict.from_list([
            #(
              "threshold",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Float,
                )),
                description: "The threshold value",
              ),
            ),
            #(
              "window_in_days",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.NumericType(
                  numeric_types.Integer,
                )),
                description: "Window period in days",
              ),
            ),
            #(
              "queries",
              ParamInfo(
                type_: accepted_types.CollectionType(collection_types.Dict(
                  accepted_types.PrimitiveType(primitive_types.String),
                  accepted_types.PrimitiveType(primitive_types.String),
                )),
                description: "Metric queries",
              ),
            ),
            #(
              "value",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.String),
                description: "The SLO value",
              ),
            ),
          ]),
        ),
        artifacts.Artifact(
          type_: artifacts.DependencyRelations,
          description: "A test dependency relations artifact",
          params: dict.from_list([
            #(
              "relationship",
              ParamInfo(
                type_: accepted_types.CollectionType(
                  collection_types.List(accepted_types.PrimitiveType(
                    primitive_types.String,
                  )),
                ),
                description: "List of related services",
              ),
            ),
            #(
              "isHard",
              ParamInfo(
                type_: accepted_types.PrimitiveType(primitive_types.Boolean),
                description: "Whether this is a hard dependency",
              ),
            ),
          ]),
        ),
      ]),
    ),
    // empty params
    #(
      path("happy_path_empty_params"),
      Ok([
        artifacts.Artifact(
          type_: artifacts.SLO,
          description: "A test SLO artifact",
          params: dict.new(),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_from_file)

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
        msg: "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.type_)",
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
        msg: "Incorrect types: expected (Field) received (Nothing) for (artifacts.0.type_), expected (Field) received (Nothing) for (artifacts.0.description), expected (Field) received (Nothing) for (artifacts.0.params)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_from_file)

  // Duplicates
  [
    #(
      path("duplicate_names"),
      Error(errors.ParserDuplicateError(msg: "Duplicate artifact names: SLO")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_from_file)

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
        msg: "Incorrect types: expected (String) received (Int) for (artifacts.0.type_)",
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
        msg: "Incorrect types: expected (AcceptedType (unknown: LolNotAType)) received (String) for (artifacts.0.params.values.type_)",
      )),
    ),
    #(
      path("wrong_type_params_value_not_accepted_type_typo"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType (unknown: Intege)) received (String) for (artifacts.0.params.values.type_)",
      )),
    ),
    #(
      path("wrong_type_params_value_not_accepted_type_illegal"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType (unknown: Optional(Optional(String)))) received (String) for (artifacts.0.params.values.type_)",
      )),
    ),
    #(
      path("wrong_type_multiple"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (String) received (Int) for (artifacts.0.type_), expected (AcceptedType (unknown: MadeUp1)) received (String) for (artifacts.0.params.values.type_)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_from_file)

  // JSON format errors - different error messages on Erlang vs JavaScript targets
  [#("json_invalid_syntax", True), #("json_empty_file", True)]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    case parse_from_file(path(file_name)) {
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
  |> test_helpers.array_based_test_executor_1(parse_from_file)

  // Empty name
  [
    #(
      path("empty_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (SLO or DependencyRelations) received (String) for (artifacts.0.type_)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(parse_from_file)
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

// ==== pretty_print_artifact ====
// * ✅ includes artifact name
// * ✅ includes artifact description
// * ✅ includes param names
// * ✅ includes param descriptions
// * ✅ includes param types
// * ✅ includes param status (required/optional/default)
pub fn pretty_print_artifact_test() {
  let artifact =
    artifacts.Artifact(
      type_: artifacts.SLO,
      description: "Test artifact description",
      params: dict.from_list([
        #(
          "my_param",
          ParamInfo(
            type_: accepted_types.PrimitiveType(primitive_types.String),
            description: "My param description",
          ),
        ),
      ]),
    )
  let output = artifacts.pretty_print_artifact(artifact)

  // Verify all expected content is present in the output
  // Each test checks if a substring is present
  [
    #("SLO", True),
    #("Test artifact description", True),
    #("my_param", True),
    #("My param description", True),
    #("String", True),
    #("required", True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(substring) {
    string.contains(output, substring)
  })
}
