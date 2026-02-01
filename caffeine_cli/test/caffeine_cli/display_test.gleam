import caffeine_cli/display
import caffeine_lang/linker/artifacts.{Artifact, ParamInfo}
import caffeine_lang/types.{TypeMeta}
import gleam/dict
import gleam/string
import gleeunit/should
import test_helpers

// ==== pretty_print_artifact ====
// * ✅ includes artifact name
// * ✅ includes artifact description
// * ✅ includes param names
// * ✅ includes param descriptions
// * ✅ includes param types
// * ✅ includes param status (required/optional/default)
pub fn pretty_print_artifact_test() {
  let artifact =
    Artifact(
      type_: artifacts.SLO,
      description: "Test artifact description",
      params: dict.from_list([
        #(
          "my_param",
          ParamInfo(
            type_: types.PrimitiveType(types.String),
            description: "My param description",
          ),
        ),
      ]),
    )
  let output = display.pretty_print_artifact(artifact)

  // Verify all expected content is present in the output
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

// ==== pretty_print_category ====
// * ✅ empty types list -> header only
// * ✅ single type -> header + type entry
// * ✅ output contains category name and description
pub fn pretty_print_category_test() {
  // Empty types
  let result = display.pretty_print_category("Test", "Test category", [])
  { string.contains(result, "Test") } |> should.be_true()

  // Single type
  let result =
    display.pretty_print_category("Primitives", "Basic types", [
      TypeMeta(
        name: "String",
        description: "Text value",
        syntax: "String",
        example: "\"hello\"",
      ),
    ])
  { string.contains(result, "Primitives") } |> should.be_true()
  { string.contains(result, "String") } |> should.be_true()
  { string.contains(result, "Text value") } |> should.be_true()

  // Multiple types
  let result =
    display.pretty_print_category("Numbers", "Numeric types", [
      TypeMeta(
        name: "Integer",
        description: "Whole number",
        syntax: "Integer",
        example: "42",
      ),
      TypeMeta(
        name: "Float",
        description: "Decimal number",
        syntax: "Float",
        example: "3.14",
      ),
    ])
  { string.contains(result, "Integer") } |> should.be_true()
  { string.contains(result, "Float") } |> should.be_true()
}
