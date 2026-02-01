import caffeine_lang/common/accepted_types
import caffeine_lang/common/primitive_types
import caffeine_lang/parser/artifacts.{ParamInfo}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import gleam/dict
import gleam/list
import gleam/string
import test_helpers

// ==== standard_library ====
// * ✅ returns two artifacts (SLO and DependencyRelations)
// * ✅ artifact types match expected
pub fn standard_library_test() {
  let result = stdlib_artifacts.standard_library()

  [
    #(list.length(result), 2),
  ]
  |> test_helpers.array_based_test_executor_1(fn(expected) { expected })

  let types =
    result
    |> list.map(fn(a) { artifacts.artifact_type_to_string(a.type_) })

  [
    #(list.contains(types, "SLO"), True),
    #(list.contains(types, "DependencyRelations"), True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(val) { val })
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
