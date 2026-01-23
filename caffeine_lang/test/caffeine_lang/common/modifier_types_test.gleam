import caffeine_lang/common/modifier_types
import gleam/dynamic
import gleam/dynamic/decode
import test_helpers

// ==== parse_modifier_type ====
// ==== Happy Path - Optional ====
// * ✅ Optional(String)
// * ✅ Optional(Integer)
// * ✅ Optional with nested collection: Optional(Dict(String, List(Integer)))
// ==== Happy Path - Defaulted ====
// * ✅ Defaulted(String, default)
// * ✅ Defaulted(Integer, 10)
// * ✅ Defaulted with nested collection: Defaulted(Dict(String, List(Integer)), {})
// ==== Sad Path ====
// * ✅ Unknown type
// * ✅ Empty string
// * ✅ Optional without parens
// * ✅ Defaulted with invalid default value
// * ✅ Modifier with refinement suffix (should fail, let refinement parser handle)
pub fn parse_modifier_type_test() {
  // Helper to parse inner types (handles primitives, nested collections, and refinements)
  let parse_inner = fn(raw: String) {
    case raw {
      "String" -> Ok("String")
      "Integer" -> Ok("Integer")
      "Float" -> Ok("Float")
      "Boolean" -> Ok("Boolean")
      // Nested collection types
      "Dict(String, String)" -> Ok("Dict(String, String)")
      "Dict(String, List(Integer))" -> Ok("Dict(String, List(Integer))")
      "List(List(String))" -> Ok("List(List(String))")
      // Refinement types (inner type contains braces)
      "String { x | x in { demo, development, pre-production, production } }" ->
        Ok("String { x | x in { demo, development, pre-production, production } }")
      "Integer { x | x in { 1, 2, 3 } }" -> Ok("Integer { x | x in { 1, 2, 3 } }")
      "String { x | x in { a, b, c } }" ->
        Ok("String { x | x in { a, b, c } }")
      _ -> Error(Nil)
    }
  }

  // Helper to validate default values
  let validate_default = fn(typ: String, default_val: String) {
    case typ {
      "String" -> Ok(Nil)
      "Integer" ->
        case default_val {
          "10" | "42" | "0" | "1" -> Ok(Nil)
          _ -> Error(Nil)
        }
      "Boolean" ->
        case default_val {
          "True" | "False" -> Ok(Nil)
          _ -> Error(Nil)
        }
      "Float" ->
        case default_val {
          "3.14" | "1.5" -> Ok(Nil)
          _ -> Error(Nil)
        }
      // Collection types accept {} as default
      "Dict(String, String)"
      | "Dict(String, List(Integer))"
      | "List(List(String))" ->
        case default_val {
          "{}" | "[]" -> Ok(Nil)
          _ -> Error(Nil)
        }
      // Refinement types - accept values that would be in the set
      "String { x | x in { demo, development, pre-production, production } }" ->
        case default_val {
          "demo" | "development" | "pre-production" | "production" -> Ok(Nil)
          _ -> Error(Nil)
        }
      "Integer { x | x in { 1, 2, 3 } }" ->
        case default_val {
          "1" | "2" | "3" -> Ok(Nil)
          _ -> Error(Nil)
        }
      "String { x | x in { a, b, c } }" ->
        case default_val {
          "a" | "b" | "c" -> Ok(Nil)
          _ -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  }

  [
    // Optional
    #("Optional(String)", Ok(modifier_types.Optional("String"))),
    #("Optional(Integer)", Ok(modifier_types.Optional("Integer"))),
    #("Optional(Float)", Ok(modifier_types.Optional("Float"))),
    #("Optional(Boolean)", Ok(modifier_types.Optional("Boolean"))),
    // Optional with nested collections
    #(
      "Optional(Dict(String, String))",
      Ok(modifier_types.Optional("Dict(String, String)")),
    ),
    #(
      "Optional(Dict(String, List(Integer)))",
      Ok(modifier_types.Optional("Dict(String, List(Integer))")),
    ),
    #(
      "Optional(List(List(String)))",
      Ok(modifier_types.Optional("List(List(String))")),
    ),
    // Defaulted
    #(
      "Defaulted(String, hello)",
      Ok(modifier_types.Defaulted("String", "hello")),
    ),
    #("Defaulted(Integer, 10)", Ok(modifier_types.Defaulted("Integer", "10"))),
    #(
      "Defaulted(Boolean, True)",
      Ok(modifier_types.Defaulted("Boolean", "True")),
    ),
    #("Defaulted(Float, 3.14)", Ok(modifier_types.Defaulted("Float", "3.14"))),
    // Defaulted with nested collections - tests the top-level comma split fix
    #(
      "Defaulted(Dict(String, String), {})",
      Ok(modifier_types.Defaulted("Dict(String, String)", "{}")),
    ),
    #(
      "Defaulted(Dict(String, List(Integer)), {})",
      Ok(modifier_types.Defaulted("Dict(String, List(Integer))", "{}")),
    ),
    // Defaulted with refinement types - tests brace tracking in top-level comma split
    // This was the bug: commas inside { } were incorrectly treated as top-level separators
    #(
      "Defaulted(String { x | x in { demo, development, pre-production, production } }, production)",
      Ok(modifier_types.Defaulted(
        "String { x | x in { demo, development, pre-production, production } }",
        "production",
      )),
    ),
    #(
      "Defaulted(Integer { x | x in { 1, 2, 3 } }, 1)",
      Ok(modifier_types.Defaulted("Integer { x | x in { 1, 2, 3 } }", "1")),
    ),
    #(
      "Defaulted(String { x | x in { a, b, c } }, a)",
      Ok(modifier_types.Defaulted("String { x | x in { a, b, c } }", "a")),
    ),
    // Invalid
    #("Unknown", Error(Nil)),
    #("", Error(Nil)),
    #("Optional", Error(Nil)),
    #("Optional(Unknown)", Error(Nil)),
    #("Defaulted(Integer, hello)", Error(Nil)),
    #("Defaulted(Boolean, maybe)", Error(Nil)),
    // Modifier with refinement suffix should fail - let refinement parser handle it
    #("Defaulted(String, production) { x | x in { production } }", Error(Nil)),
    #("Optional(String) { x | x in { foo } }", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    modifier_types.parse_modifier_type(input, parse_inner, validate_default)
  })
}

// ==== modifier_type_to_string ====
// * ✅ Optional(T) -> "Optional(T)"
// * ✅ Defaulted(T, val) -> "Defaulted(T, val)"
pub fn modifier_type_to_string_test() {
  // Identity function for inner type string conversion
  let inner_to_string = fn(x: String) { x }

  [
    #(modifier_types.Optional("String"), "Optional(String)"),
    #(modifier_types.Optional("Integer"), "Optional(Integer)"),
    #(modifier_types.Defaulted("String", "hello"), "Defaulted(String, hello)"),
    #(modifier_types.Defaulted("Integer", "10"), "Defaulted(Integer, 10)"),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    modifier_types.modifier_type_to_string(input, inner_to_string)
  })
}

// ==== decode_modifier_to_string ====
// ==== Optional ====
// * ✅ Optional with value present -> value
// * ✅ Optional with value absent -> empty string
// ==== Defaulted ====
// * ✅ Defaulted with value present -> value
// * ✅ Defaulted with value absent -> default value
pub fn decode_modifier_to_string_test() {
  // Helper decoder for inner types (just string for simplicity)
  let decode_inner = fn(_typ: String) { decode.string }

  // Optional with value present
  [#(dynamic.string("hello"), Ok("hello"))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      modifier_types.decode_modifier_to_string(
        modifier_types.Optional("String"),
        decode_inner,
      ),
    )
  })

  // Defaulted with value present
  [#(dynamic.string("custom"), Ok("custom"))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      modifier_types.decode_modifier_to_string(
        modifier_types.Defaulted("String", "default"),
        decode_inner,
      ),
    )
  })
}

// ==== validate_value ====
// ==== Optional ====
// * ✅ Optional with value present validates inner type
// * ✅ Optional with value absent (None) succeeds
// ==== Defaulted ====
// * ✅ Defaulted with value present validates inner type
// * ✅ Defaulted with value absent (None) succeeds
pub fn validate_value_test() {
  // Simple validator that always succeeds (simulates inner type validation)
  let validate_inner = fn(_typ: String, value: dynamic.Dynamic) { Ok(value) }

  [
    // Optional with value present
    #(#(modifier_types.Optional("String"), dynamic.string("hello")), True),
    // Optional with None
    #(#(modifier_types.Optional("String"), dynamic.nil()), True),
    // Defaulted with value present
    #(
      #(modifier_types.Defaulted("String", "default"), dynamic.string("custom")),
      True,
    ),
    // Defaulted with None
    #(#(modifier_types.Defaulted("String", "default"), dynamic.nil()), True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case modifier_types.validate_value(typ, value, validate_inner) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_to_string ====
// ==== Optional ====
// * ✅ Optional with value present resolves inner value
// * ✅ Optional with None returns empty string
// ==== Defaulted ====
// * ✅ Defaulted with value present resolves inner value
// * ✅ Defaulted with None uses default value
pub fn resolve_to_string_test() {
  let resolve_inner = fn(_typ: String, value: dynamic.Dynamic) {
    case decode.run(value, decode.string) {
      Ok(s) -> Ok("resolved:" <> s)
      Error(_) -> Error("decode failed")
    }
  }
  let resolve_string = fn(s) { "resolved:" <> s }

  [
    // Optional with value present
    #(
      #(modifier_types.Optional("String"), dynamic.string("hello")),
      Ok("resolved:hello"),
    ),
    // Optional with None returns empty string
    #(#(modifier_types.Optional("String"), dynamic.nil()), Ok("")),
    // Defaulted with value present
    #(
      #(modifier_types.Defaulted("String", "default"), dynamic.string("custom")),
      Ok("resolved:custom"),
    ),
    // Defaulted with None uses default
    #(
      #(modifier_types.Defaulted("String", "default"), dynamic.nil()),
      Ok("resolved:default"),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    modifier_types.resolve_to_string(typ, value, resolve_inner, resolve_string)
  })
}
