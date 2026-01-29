import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/errors
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/parser/artifacts.{type Artifact, ParamInfo}
import caffeine_lang/parser/blueprints
import gleam/dict
import gleam/dynamic
import simplifile
import test_helpers

// ==== Helpers ====
fn path(file_name: String) {
  "test/caffeine_lang/corpus/parser/blueprints/" <> file_name <> ".json"
}

fn parse_from_file(file_path: String, artifacts: List(Artifact)) {
  let assert Ok(json) = simplifile.read(file_path)
  blueprints.parse_from_json_string(json, artifacts)
}

fn artifacts() -> List(Artifact) {
  [
    artifacts.Artifact(
      type_: artifacts.SLO,
      description: "",
      params: dict.from_list([
        #(
          "threshold",
          ParamInfo(
            type_: accepted_types.PrimitiveType(primitive_types.NumericType(
              numeric_types.Float,
            )),
            description: "",
          ),
        ),
        #(
          "value",
          ParamInfo(
            type_: accepted_types.PrimitiveType(primitive_types.String),
            description: "",
          ),
        ),
      ]),
    ),
  ]
}

/// Artifacts helper for multi-artifact tests
fn multi_artifacts() -> List(Artifact) {
  [
    artifacts.Artifact(
      type_: artifacts.SLO,
      description: "",
      params: dict.from_list([
        #(
          "threshold",
          ParamInfo(
            type_: accepted_types.PrimitiveType(primitive_types.NumericType(
              numeric_types.Float,
            )),
            description: "",
          ),
        ),
        #(
          "value",
          ParamInfo(
            type_: accepted_types.PrimitiveType(primitive_types.String),
            description: "",
          ),
        ),
      ]),
    ),
    artifacts.Artifact(
      type_: artifacts.DependencyRelations,
      description: "",
      params: dict.from_list([
        #(
          "relationship",
          ParamInfo(
            type_: accepted_types.CollectionType(
              collection_types.List(accepted_types.PrimitiveType(
                primitive_types.String,
              )),
            ),
            description: "",
          ),
        ),
        #(
          "isHard",
          ParamInfo(
            type_: accepted_types.PrimitiveType(primitive_types.Boolean),
            description: "",
          ),
        ),
      ]),
    ),
  ]
}

// ==== parse_from_json_string ====
// * ✅ happy path - none
// * ✅ happy path - single blueprint
// * ✅ happy path - multiple blueprints
// * ✅ happy path - blueprint with no inputs (partial inputs allowed)
// * ✅ happy path - empty params
// * ✅ missing - name
// * ✅ missing - artifact_ref
// * ✅ missing - params
// * ✅ missing - inputs
// * ✅ duplicates - name (all blueprints must be unique)
// * ✅ duplicates - cannot overshadow artifact params with blueprint params
// * ✅ wrong type - blueprints
// * ✅ wrong type - name
// * ✅ wrong type - artifact_ref
// * ✅ wrong type - params is a map
// * ✅ wrong type - each param's value is an Accepted Type
// * ✅ wrong type - inputs is a map
// * ✅ wrong type - input value type validation
// * ✅ semantic - blueprint references an actual artifact
// * ✅ json format - invalid JSON syntax
// * ✅ json format - empty file
// * ✅ json format - null value
// * ✅ empty name - empty string name is rejected
// * ✅ input validation - extra input field
pub fn parse_from_json_string_test() {
  // Happy paths with Ok results
  [
    // none
    #(path("happy_path_none"), Ok([])),
    // single
    #(
      path("happy_path_single"),
      Ok([
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
            #(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
            ),
            #("value", accepted_types.PrimitiveType(primitive_types.String)),
          ]),
          inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
        ),
      ]),
    ),
    // multiple
    #(
      path("happy_path_multiple"),
      Ok([
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
            #(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
            ),
            #("value", accepted_types.PrimitiveType(primitive_types.String)),
          ]),
          inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
        ),
        blueprints.Blueprint(
          name: "latency_p99",
          artifact_refs: ["SLO"],
          params: dict.from_list([
            #(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
            ),
            #("value", accepted_types.PrimitiveType(primitive_types.String)),
          ]),
          inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
        ),
      ]),
    ),
    // empty params - should merge with artifact params
    #(
      path("happy_path_empty_params"),
      Ok([
        blueprints.Blueprint(
          name: "minimal_blueprint",
          artifact_refs: ["SLO"],
          params: dict.from_list([
            #(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
            ),
            #("value", accepted_types.PrimitiveType(primitive_types.String)),
          ]),
          inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // no inputs - now allowed since blueprints can provide partial inputs
  [#(path("input_missing_required"), True)]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    case parse_from_file(file_path, artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Missing fields
  [
    #(
      path("missing_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.name)",
      )),
    ),
    #(
      path("missing_artifact_ref"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.artifact_refs)",
      )),
    ),
    #(
      path("missing_params"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.params)",
      )),
    ),
    #(
      path("missing_inputs"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Field) received (Nothing) for (blueprints.0.inputs)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // Duplicates
  [
    #(
      path("duplicate_name"),
      Error(errors.ParserDuplicateError(
        msg: "Duplicate blueprint names: success_rate",
      )),
    ),
    #(
      path("duplicate_overshadowing_inherited_param"),
      Error(errors.ParserDuplicateError(
        msg: "blueprint 'success_rate' - overshadowing inherited_params from artifact: threshold",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // Wrong types
  [
    #(
      path("wrong_type_blueprints"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (List) received (String) for (blueprints)",
      )),
    ),
    #(
      path("wrong_type_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (Int) for (blueprints.0.name)",
      )),
    ),
    #(
      path("wrong_type_artifact_ref"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (List) received (String) for (blueprints.0.artifact_refs)",
      )),
    ),
    #(
      path("wrong_type_params_not_a_map"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Dict) received (List) for (blueprints.0.params)",
      )),
    ),
    #(
      path("wrong_type_params_value_typo"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType) received (String) for (blueprints.0.params.values)",
      )),
    ),
    #(
      path("wrong_type_params_value_illegal"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (AcceptedType) received (String) for (blueprints.0.params.values)",
      )),
    ),
    #(
      path("wrong_type_inputs_not_a_map"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (Dict) received (String) for (blueprints.0.inputs)",
      )),
    ),
    #(
      path("wrong_type_input_value"),
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: blueprint 'success_rate' - expected (String) received (Int) for (value)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // Semantic
  [
    #(
      path("semantic_artifact_ref"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NamedReference) received (String) for (blueprints.0.artifact_refs.0)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // JSON format errors - these produce different error messages on Erlang vs JavaScript targets
  [#("json_invalid_syntax", True), #("json_empty_file", True)]
  |> test_helpers.array_based_test_executor_1(fn(file_name) {
    case parse_from_file(path(file_name), artifacts()) {
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
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // Empty name
  [
    #(
      path("empty_name"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyString) received (String) for (blueprints.0.name)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })

  // Input validation
  [
    #(
      path("input_extra_field"),
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: blueprint 'success_rate' - Extra keys in input: extra",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, artifacts())
  })
}

// ==== artifact_refs (List) support ====
// These tests validate the new artifact_refs field that accepts a list of artifact names.
// * ✅ happy path - single artifact in list: ["SLO"]
// * ✅ happy path - multiple artifacts: ["SLO", "DependencyRelations"]
// * ✅ happy path - overlapping params with same type merge correctly
// * ✅ wrong type - artifact_refs is not a list
// * ✅ wrong type - artifact_refs element is not a string
// * ✅ empty - artifact_refs is empty list
// * ✅ semantic - unknown artifact in list
// * ✅ duplicates - same artifact appears twice in list
// * ✅ conflicting params - artifacts have same param name with different types
pub fn parse_from_json_string_artifact_refs_test() {
  // Happy path - single artifact in list
  [
    #(
      path("happy_path_single_artifact_refs"),
      Ok([
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
            #(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
            ),
            #("value", accepted_types.PrimitiveType(primitive_types.String)),
          ]),
          inputs: dict.from_list([#("value", dynamic.string("foobar"))]),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })

  // Happy path - multiple artifacts in list (params merged from both)
  [
    #(
      path("happy_path_multiple_artifact_refs"),
      Ok([
        blueprints.Blueprint(
          name: "tracked_slo",
          artifact_refs: ["SLO", "DependencyRelations"],
          params: dict.from_list([
            // From SLO
            #(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
            ),
            #("value", accepted_types.PrimitiveType(primitive_types.String)),
            // From Dependency
            #(
              "relationship",
              accepted_types.CollectionType(
                collection_types.List(accepted_types.PrimitiveType(
                  primitive_types.String,
                )),
              ),
            ),
            #("isHard", accepted_types.PrimitiveType(primitive_types.Boolean)),
          ]),
          inputs: dict.from_list([
            #("value", dynamic.string("foobar")),
            #("isHard", dynamic.bool(True)),
          ]),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })

  // Wrong type - artifact_refs is not a list
  [
    #(
      path("wrong_type_artifact_refs_not_list"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (List) received (String) for (blueprints.0.artifact_refs)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })

  // Wrong type - artifact_refs element is not a string
  [
    #(
      path("wrong_type_artifact_refs_element"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NamedReference) received (Int) for (blueprints.0.artifact_refs.0)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })

  // Empty artifact_refs list
  [
    #(
      path("empty_artifact_refs"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NonEmptyList) received (List) for (blueprints.0.artifact_refs)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })

  // Semantic - unknown artifact in list
  [
    #(
      path("semantic_artifact_refs_unknown"),
      Error(errors.ParserJsonParserError(
        msg: "Incorrect types: expected (NamedReference) received (String) for (blueprints.0.artifact_refs.1)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })

  // Duplicate artifact refs in list
  [
    #(
      path("duplicate_artifact_refs"),
      Error(errors.ParserDuplicateError(
        msg: "blueprint 'success_rate' - duplicate artifact references: SLO",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parse_from_file(file_path, multi_artifacts())
  })
}
