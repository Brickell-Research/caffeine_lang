import caffeine_lang/type_info.{TypeMeta}
import gleam/string
import gleeunit/should

// ==== pretty_print_category ====
// * ✅ empty types list -> header only
// * ✅ single type -> header + type entry
// * ✅ output contains category name and description
pub fn pretty_print_category_test() {
  // Empty types
  let result = type_info.pretty_print_category("Test", "Test category", [])
  { string.contains(result, "Test") } |> should.be_true()

  // Single type
  let result =
    type_info.pretty_print_category("Primitives", "Basic types", [
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
    type_info.pretty_print_category("Numbers", "Numeric types", [
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
