import caffeine_lang/types.{
  type AcceptedTypes, type PrimitiveTypes, Boolean, CollectionType, Defaulted,
  Dict, Float, InclusiveRange, Integer, List, ModifierType, NumericType, OneOf,
  Optional, PrimitiveType, RecordType, RefinementType, SemanticType, String, URL,
}
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import gleeunit/should
import test_helpers

// ===========================================================================
// NumericTypes tests
// ===========================================================================

// ==== parse_numeric_type ====
// ==== Happy Path ====
// * ✅ Float
// * ✅ Integer
// ==== Sad Path ====
// * ✅ Unknown type
// * ✅ Empty string
pub fn parse_numeric_type_test() {
  [
    #("Float", Ok(Float)),
    #("Integer", Ok(Integer)),
    #("Unknown", Error(Nil)),
    #("", Error(Nil)),
    #("float", Error(Nil)),
    #("integer", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(types.parse_numeric_type)
}

// ==== numeric_type_to_string ====
// * ✅ Float -> "Float"
// * ✅ Integer -> "Integer"
pub fn numeric_type_to_string_test() {
  [#(Float, "Float"), #(Integer, "Integer")]
  |> test_helpers.array_based_test_executor_1(types.numeric_type_to_string)
}

// ==== validate_numeric_default_value ====
// ==== Happy Path ====
// * ✅ Integer with valid int string
// * ✅ Float with valid float string
// ==== Sad Path ====
// * ✅ Integer with non-integer string
// * ✅ Float with non-float string
pub fn validate_numeric_default_value_test() {
  [
    // Integer
    #(#(Integer, "42"), Ok(Nil)),
    #(#(Integer, "-10"), Ok(Nil)),
    #(#(Integer, "0"), Ok(Nil)),
    #(#(Integer, "hello"), Error(Nil)),
    #(#(Integer, "3.14"), Error(Nil)),
    // Float
    #(#(Float, "3.14"), Ok(Nil)),
    #(#(Float, "-1.5"), Ok(Nil)),
    #(#(Float, "hello"), Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_numeric_default_value(input.0, input.1)
  })
}

// ==== validate_numeric_value ====
// ==== Happy Path ====
// * ✅ Integer with valid int value
// * ✅ Float with valid float value
// ==== Sad Path ====
// * ✅ Integer with non-integer value
// * ✅ Float with non-float value (String only - Int/Float distinction is platform-specific)
pub fn validate_numeric_value_test() {
  let int_val = value.IntValue(42)
  let float_val = value.FloatValue(3.14)
  let string_val = value.StringValue("hello")

  // Integer validation
  [
    #(#(Integer, int_val), Ok(int_val)),
    #(
      #(Integer, string_val),
      Error([types.ValidationError(expected: "Int", found: "String", path: [])]),
    ),
    #(
      #(Integer, float_val),
      Error([types.ValidationError(expected: "Int", found: "Float", path: [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_numeric_value(input.0, input.1)
  })

  // Float validation
  // Note: Int -> Float validation is platform-specific (JS doesn't distinguish Int/Float)
  [
    #(#(Float, float_val), Ok(float_val)),
    #(
      #(Float, string_val),
      Error([
        types.ValidationError(expected: "Float", found: "String", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_numeric_value(input.0, input.1)
  })
}

// ==== validate_in_range ====
// ==== Happy Path ====
// * ✅ Integer value within range
// * ✅ Integer value at lower bound
// * ✅ Integer value at upper bound
// * ✅ Float value within range
// * ✅ Float value at lower bound
// * ✅ Float value at upper bound
// ==== Sad Path ====
// * ✅ Integer value out of range
// * ✅ Float value out of range
// * ✅ Invalid value string for type
pub fn validate_in_range_test() {
  // Integer - happy path
  [
    #(#(Integer, "50", "0", "100"), Ok(Nil)),
    #(#(Integer, "0", "0", "100"), Ok(Nil)),
    #(#(Integer, "100", "0", "100"), Ok(Nil)),
    #(#(Integer, "-5", "-10", "10"), Ok(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Integer - sad path (out of range)
  [
    #(
      #(Integer, "-1", "0", "100"),
      Error([
        types.ValidationError(expected: "0 <= x <= 100", found: "-1", path: []),
      ]),
    ),
    #(
      #(Integer, "-20", "-10", "10"),
      Error([
        types.ValidationError(
          expected: "-10 <= x <= 10",
          found: "-20",
          path: [],
        ),
      ]),
    ),
    #(
      #(Integer, "101", "0", "100"),
      Error([
        types.ValidationError(expected: "0 <= x <= 100", found: "101", path: []),
      ]),
    ),
    #(
      #(Integer, "15", "-10", "10"),
      Error([
        types.ValidationError(expected: "-10 <= x <= 10", found: "15", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Integer - sad path (invalid value)
  [
    #(
      #(Integer, "hello", "0", "100"),
      Error([
        types.ValidationError(expected: "Integer", found: "hello", path: []),
      ]),
    ),
    #(
      #(Integer, "3.14", "0", "100"),
      Error([
        types.ValidationError(expected: "Integer", found: "3.14", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - happy path
  [
    #(#(Float, "0.5", "0.0", "1.0"), Ok(Nil)),
    #(#(Float, "0.0", "0.0", "1.0"), Ok(Nil)),
    #(#(Float, "1.0", "0.0", "1.0"), Ok(Nil)),
    #(#(Float, "-0.5", "-1.0", "1.0"), Ok(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - sad path (out of range)
  [
    #(
      #(Float, "-0.1", "0.0", "1.0"),
      Error([
        types.ValidationError(
          expected: "0.0 <= x <= 1.0",
          found: "-0.1",
          path: [],
        ),
      ]),
    ),
    #(
      #(Float, "1.1", "0.0", "1.0"),
      Error([
        types.ValidationError(
          expected: "0.0 <= x <= 1.0",
          found: "1.1",
          path: [],
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - sad path (invalid value)
  [
    #(
      #(Float, "hello", "0.0", "1.0"),
      Error([types.ValidationError(expected: "Float", found: "hello", path: [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_in_range(input.0, input.1, input.2, input.3)
  })
}

// ===========================================================================
// SemanticStringTypes tests
// ===========================================================================

// ==== parse_semantic_type ====
// ==== Happy Path ====
// * ✅ URL
// ==== Sad Path ====
// * ✅ lowercase url
// * ✅ Empty string
pub fn parse_semantic_type_test() {
  [#("URL", Ok(URL)), #("url", Error(Nil)), #("", Error(Nil))]
  |> test_helpers.array_based_test_executor_1(types.parse_semantic_type)
}

// ==== semantic_type_to_string ====
// * ✅ URL -> "URL"
pub fn semantic_type_to_string_test() {
  [#(URL, "URL")]
  |> test_helpers.array_based_test_executor_1(types.semantic_type_to_string)
}

// ==== validate_semantic_default_value ====
// ==== Happy Path ====
// * ✅ Valid https URL
// * ✅ Valid http URL
// ==== Sad Path ====
// * ✅ Non-URL string
// * ✅ Empty string
pub fn validate_semantic_default_value_test() {
  [
    #(#(SemanticType(URL), "https://example.com"), Ok(Nil)),
    #(#(SemanticType(URL), "http://example.com"), Ok(Nil)),
    #(
      #(SemanticType(URL), "https://wiki.example.com/runbook/auth-latency"),
      Ok(Nil),
    ),
    #(#(SemanticType(URL), "not-a-url"), Error(Nil)),
    #(#(SemanticType(URL), ""), Error(Nil)),
    #(#(SemanticType(URL), "ftp://example.com"), Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_primitive_default_value(input.0, input.1)
  })
}

// ==== validate_semantic_value ====
// ==== Happy Path ====
// * ✅ String value with valid URL
// ==== Sad Path ====
// * ✅ String value with invalid URL
// * ✅ Non-string value
pub fn validate_semantic_value_test() {
  let valid_url = value.StringValue("https://example.com")
  let invalid_url = value.StringValue("not-a-url")
  let int_val = value.IntValue(42)

  // Valid URL
  [#(#(PrimitiveType(SemanticType(URL)), valid_url), Ok(valid_url))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_value(input.0, input.1)
  })

  // Invalid URL string
  [
    #(
      #(PrimitiveType(SemanticType(URL)), invalid_url),
      Error([
        types.ValidationError(
          expected: "URL (starting with http:// or https://)",
          found: "not-a-url",
          path: [],
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_value(input.0, input.1)
  })

  // Non-string value
  [
    #(
      #(PrimitiveType(SemanticType(URL)), int_val),
      Error([
        types.ValidationError(expected: "String", found: "Int", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_value(input.0, input.1)
  })
}

// ===========================================================================
// PrimitiveTypes tests
// ===========================================================================

// ==== parse_primitive_type ====
// * ✅ Boolean
// * ✅ String
// * ✅ delegates to numeric_types for Float/Integer
// * ✅ Unknown type returns Error
pub fn parse_primitive_type_test() {
  [
    #("Boolean", Ok(Boolean)),
    #("String", Ok(String)),
    // Integration: delegates to numeric_types
    #("Float", Ok(NumericType(Float))),
    #("Integer", Ok(NumericType(Integer))),
    // Sad path
    #("Unknown", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(types.parse_primitive_type)
}

// ==== primitive_type_to_string ====
// * ✅ Boolean -> "Boolean"
// * ✅ String -> "String"
// * ✅ delegates to numeric_types for NumericType
pub fn primitive_type_to_string_test() {
  [
    #(Boolean, "Boolean"),
    #(String, "String"),
    // Integration: delegates to numeric_types
    #(NumericType(Float), "Float"),
  ]
  |> test_helpers.array_based_test_executor_1(types.primitive_type_to_string)
}

// ==== validate_primitive_default_value ====
// * ✅ Boolean with True/False
// * ✅ Boolean with invalid value
// * ✅ String accepts any value
// * ✅ delegates to numeric_types for NumericType
pub fn validate_primitive_default_value_test() {
  [
    // Boolean
    #(#(Boolean, "True"), Ok(Nil)),
    #(#(Boolean, "False"), Ok(Nil)),
    #(#(Boolean, "invalid"), Error(Nil)),
    // String
    #(#(String, "anything"), Ok(Nil)),
    // Integration: delegates to numeric_types
    #(#(NumericType(Integer), "42"), Ok(Nil)),
    #(#(NumericType(Integer), "bad"), Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.validate_primitive_default_value(input.0, input.1)
  })
}

// ==== validate_primitive_value ====
// * ✅ Boolean validates bool
// * ✅ String validates string
// * ✅ delegates to numeric_types for NumericType
pub fn validate_primitive_value_test() {
  [
    #(#(PrimitiveType(Boolean), value.BoolValue(True)), True),
    #(#(PrimitiveType(Boolean), value.StringValue("not bool")), False),
    #(#(PrimitiveType(String), value.StringValue("hello")), True),
    #(#(PrimitiveType(String), value.IntValue(42)), False),
    // Integration: delegates to numeric_types
    #(#(PrimitiveType(NumericType(Integer)), value.IntValue(42)), True),
    #(#(PrimitiveType(NumericType(Float)), value.FloatValue(3.14)), True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_primitive_to_string ====
// * ✅ Boolean resolves with resolver
// * ✅ String resolves with resolver
// * ✅ delegates to numeric_types for NumericType
pub fn resolve_primitive_to_string_test() {
  let resolver = fn(s) { "resolved:" <> s }

  [
    #(#(Boolean, value.BoolValue(True)), "resolved:True"),
    #(#(String, value.StringValue("hello")), "resolved:hello"),
    // Integration: delegates to numeric_types
    #(#(NumericType(Integer), value.IntValue(42)), "resolved:42"),
    #(#(NumericType(Float), value.FloatValue(3.14)), "resolved:3.14"),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    types.resolve_primitive_to_string(typ, value, resolver)
  })
}

// ==== parse_refinement_compatible_primitive ====
// * ✅ String -> Ok(String)
// * ✅ Integer -> Ok(NumericType(Integer))
// * ✅ Float -> Ok(NumericType(Float))
// * ✅ Boolean -> Error(Nil) (excluded from refinements)
// * ✅ URL -> Error(Nil) (excluded from refinements)
// * ✅ Unknown -> Error(Nil)
pub fn parse_refinement_compatible_primitive_test() {
  [
    #("String", Ok(String)),
    #("Integer", Ok(NumericType(Integer))),
    #("Float", Ok(NumericType(Float))),
    #("Boolean", Error(Nil)),
    #("URL", Error(Nil)),
    #("Unknown", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(
    types.parse_refinement_compatible_primitive,
  )
}

// ==== primitive_all_type_metas ====
// * ✅ returns non-empty list with expected type names
pub fn primitive_all_type_metas_test() {
  let metas = types.all_type_metas()
  { metas != [] } |> should.be_true()

  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "String") |> should.be_true()
  list.contains(names, "Integer") |> should.be_true()
  list.contains(names, "Float") |> should.be_true()
}

// ===========================================================================
// CollectionTypes tests
// ===========================================================================

// ==== parse_collection_type ====
// ==== Happy Path ====
// * ✅ List(String)
// * ✅ List(Integer)
// * ✅ Dict(String, String)
// * ✅ Dict(String, Integer)
// * ✅ Dict(String, List(Integer)) - nested collection
// * ✅ Dict(String, Dict(String, Integer)) - deeply nested
// * ✅ List(List(String)) - nested list
// ==== Sad Path ====
// * ✅ Unknown type
// * ✅ Empty string
// * ✅ List without parens
// * ✅ List with invalid inner type
pub fn parse_collection_type_test() {
  // Helper to parse inner types (handles primitives and nested collections)
  let parse_inner = fn(raw: String) {
    case raw {
      "String" -> Ok("String")
      "Integer" -> Ok("Integer")
      "Float" -> Ok("Float")
      "Boolean" -> Ok("Boolean")
      "List(String)" -> Ok("List(String)")
      "List(Integer)" -> Ok("List(Integer)")
      "Dict(String, Integer)" -> Ok("Dict(String, Integer)")
      _ -> Error(Nil)
    }
  }

  [
    #("List(String)", Ok(List("String"))),
    #("List(Integer)", Ok(List("Integer"))),
    #("List(Float)", Ok(List("Float"))),
    #("List(Boolean)", Ok(List("Boolean"))),
    #("Dict(String, String)", Ok(Dict("String", "String"))),
    #("Dict(String, Integer)", Ok(Dict("String", "Integer"))),
    #("Dict(Integer, String)", Ok(Dict("Integer", "String"))),
    // Nested collections
    #("Dict(String, List(Integer))", Ok(Dict("String", "List(Integer)"))),
    #(
      "Dict(String, Dict(String, Integer))",
      Ok(Dict("String", "Dict(String, Integer)")),
    ),
    #("List(List(String))", Ok(List("List(String)"))),
    // Sad paths
    #("Unknown", Error(Nil)),
    #("", Error(Nil)),
    #("List", Error(Nil)),
    #("List(Unknown)", Error(Nil)),
    #("Dict(Unknown, String)", Error(Nil)),
    #("Dict(String, Unknown)", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.parse_collection_type(input, parse_inner)
  })
}

// ==== collection_type_to_string ====
// * ✅ List(T) -> "List(T)"
// * ✅ Dict(K, V) -> "Dict(K, V)"
pub fn collection_type_to_string_test() {
  [
    #(CollectionType(List(PrimitiveType(String))), "List(String)"),
    #(
      CollectionType(List(PrimitiveType(NumericType(Integer)))),
      "List(Integer)",
    ),
    #(
      CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
      "Dict(String, String)",
    ),
    #(
      CollectionType(Dict(
        PrimitiveType(String),
        PrimitiveType(NumericType(Integer)),
      )),
      "Dict(String, Integer)",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.accepted_type_to_string(input)
  })
}

// ==== validate_collection_value ====
// * ✅ List validates list of inner type
// * ✅ List rejects non-list
// * ✅ Dict validates dict with inner types
// * ✅ Dict rejects non-dict
pub fn validate_collection_value_test() {
  [
    // List happy path
    #(
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.ListValue([value.IntValue(1), value.IntValue(2)]),
      ),
      True,
    ),
    // List sad path - not a list
    #(
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.StringValue("not a list"),
      ),
      False,
    ),
    // Dict happy path
    #(
      #(
        CollectionType(Dict(
          PrimitiveType(String),
          PrimitiveType(NumericType(Integer)),
        )),
        value.DictValue(dict.from_list([#("a", value.IntValue(1))])),
      ),
      True,
    ),
    // Dict sad path - not a dict
    #(
      #(
        CollectionType(Dict(
          PrimitiveType(String),
          PrimitiveType(NumericType(Integer)),
        )),
        value.StringValue("not a dict"),
      ),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_collection_to_string ====
// * ✅ List resolves with list resolver
// * ✅ Dict returns error (unsupported)
pub fn resolve_collection_to_string_test() {
  let string_resolver = fn(s) { s }
  let list_resolver = fn(l) { "list:[" <> string.join(l, ",") <> "]" }

  [
    // List happy path
    #(
      #(
        CollectionType(List(PrimitiveType(String))),
        value.ListValue([value.StringValue("a"), value.StringValue("b")]),
      ),
      Ok("list:[a,b]"),
    ),
    // Dict returns error
    #(
      #(
        CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
        value.ListValue([]),
      ),
      Error(
        "Unsupported templatized variable type: Dict(String, String). Dict support is pending, open an issue if this is a desired use case.",
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, string_resolver, list_resolver)
  })
}

// ==== collection_all_type_metas ====
// * ✅ returns entries for List and Dict
pub fn collection_all_type_metas_test() {
  let metas = types.all_type_metas()
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Dict") |> should.be_true()
}

// ===========================================================================
// ModifierTypes tests
// ===========================================================================

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
        Ok(
          "String { x | x in { demo, development, pre-production, production } }",
        )
      "Integer { x | x in { 1, 2, 3 } }" ->
        Ok("Integer { x | x in { 1, 2, 3 } }")
      "String { x | x in { a, b, c } }" -> Ok("String { x | x in { a, b, c } }")
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
    #("Optional(String)", Ok(Optional("String"))),
    #("Optional(Integer)", Ok(Optional("Integer"))),
    #("Optional(Float)", Ok(Optional("Float"))),
    #("Optional(Boolean)", Ok(Optional("Boolean"))),
    // Optional with nested collections
    #("Optional(Dict(String, String))", Ok(Optional("Dict(String, String)"))),
    #(
      "Optional(Dict(String, List(Integer)))",
      Ok(Optional("Dict(String, List(Integer))")),
    ),
    #("Optional(List(List(String)))", Ok(Optional("List(List(String))"))),
    // Defaulted
    #("Defaulted(String, hello)", Ok(Defaulted("String", "hello"))),
    #("Defaulted(Integer, 10)", Ok(Defaulted("Integer", "10"))),
    #("Defaulted(Boolean, True)", Ok(Defaulted("Boolean", "True"))),
    #("Defaulted(Float, 3.14)", Ok(Defaulted("Float", "3.14"))),
    // Defaulted with nested collections - tests the top-level comma split fix
    #(
      "Defaulted(Dict(String, String), {})",
      Ok(Defaulted("Dict(String, String)", "{}")),
    ),
    #(
      "Defaulted(Dict(String, List(Integer)), {})",
      Ok(Defaulted("Dict(String, List(Integer))", "{}")),
    ),
    // Defaulted with refinement types - tests brace tracking in top-level comma split
    #(
      "Defaulted(String { x | x in { demo, development, pre-production, production } }, production)",
      Ok(Defaulted(
        "String { x | x in { demo, development, pre-production, production } }",
        "production",
      )),
    ),
    #(
      "Defaulted(Integer { x | x in { 1, 2, 3 } }, 1)",
      Ok(Defaulted("Integer { x | x in { 1, 2, 3 } }", "1")),
    ),
    #(
      "Defaulted(String { x | x in { a, b, c } }, a)",
      Ok(Defaulted("String { x | x in { a, b, c } }", "a")),
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
    types.parse_modifier_type(input, parse_inner, validate_default)
  })
}

// ==== modifier_type_to_string ====
// * ✅ Optional(T) -> "Optional(T)"
// * ✅ Defaulted(T, val) -> "Defaulted(T, val)"
pub fn modifier_type_to_string_test() {
  [
    #(ModifierType(Optional(PrimitiveType(String))), "Optional(String)"),
    #(
      ModifierType(Optional(PrimitiveType(NumericType(Integer)))),
      "Optional(Integer)",
    ),
    #(
      ModifierType(Defaulted(PrimitiveType(String), "hello")),
      "Defaulted(String, hello)",
    ),
    #(
      ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "10")),
      "Defaulted(Integer, 10)",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.accepted_type_to_string(input)
  })
}

// ==== validate_modifier_value ====
// ==== Optional ====
// * ✅ Optional with value present validates inner type
// * ✅ Optional with value absent (None) succeeds
// ==== Defaulted ====
// * ✅ Defaulted with value present validates inner type
// * ✅ Defaulted with value absent (None) succeeds
pub fn validate_modifier_value_test() {
  [
    // Optional with value present
    #(
      #(
        ModifierType(Optional(PrimitiveType(String))),
        value.StringValue("hello"),
      ),
      True,
    ),
    // Optional with None
    #(#(ModifierType(Optional(PrimitiveType(String))), value.NilValue), True),
    // Defaulted with value present
    #(
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.StringValue("custom"),
      ),
      True,
    ),
    // Defaulted with None
    #(
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.NilValue,
      ),
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_modifier_to_string ====
// ==== Optional ====
// * ✅ Optional with value present resolves inner value
// * ✅ Optional with None returns empty string
// ==== Defaulted ====
// * ✅ Defaulted with value present resolves inner value
// * ✅ Defaulted with None uses default value
pub fn resolve_modifier_to_string_test() {
  let resolve_string = fn(s) { "resolved:" <> s }
  let resolve_list = fn(l) { string.join(l, ",") }

  [
    // Optional with value present
    #(
      #(
        ModifierType(Optional(PrimitiveType(String))),
        value.StringValue("hello"),
      ),
      Ok("resolved:hello"),
    ),
    // Optional with None returns empty string
    #(#(ModifierType(Optional(PrimitiveType(String))), value.NilValue), Ok("")),
    // Defaulted with value present
    #(
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.StringValue("custom"),
      ),
      Ok("resolved:custom"),
    ),
    // Defaulted with None uses default
    #(
      #(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        value.NilValue,
      ),
      Ok("resolved:default"),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, resolve_string, resolve_list)
    |> result_to_ok_string_from_string_error
  })
}

// ==== modifier_all_type_metas ====
// * ✅ returns entries for Optional and Defaulted
pub fn modifier_all_type_metas_test() {
  let metas = types.all_type_metas()
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Optional") |> should.be_true()
  list.contains(names, "Defaulted") |> should.be_true()
}

// ==== modifier_try_each_inner ====
// * ✅ Optional calls f with inner type
// * ✅ Defaulted calls f with inner type
// * ✅ Error propagation
pub fn modifier_try_each_inner_test() {
  let always_ok = fn(_) { Ok(Nil) }

  types.try_each_inner(ModifierType(Optional(PrimitiveType(String))), always_ok)
  |> should.equal(Ok(Nil))

  types.try_each_inner(
    ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "10")),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  let always_err = fn(_) { Error("fail") }
  types.try_each_inner(
    ModifierType(Optional(PrimitiveType(String))),
    always_err,
  )
  |> should.equal(Error("fail"))
}

// ==== modifier_map_inner ====
// * ✅ Optional transforms inner type
// * ✅ Defaulted transforms inner type, preserves default
pub fn modifier_map_inner_test() {
  let to_bool = fn(_) { PrimitiveType(Boolean) }

  types.map_inner(ModifierType(Optional(PrimitiveType(String))), to_bool)
  |> should.equal(ModifierType(Optional(PrimitiveType(Boolean))))

  types.map_inner(
    ModifierType(Defaulted(PrimitiveType(String), "hello")),
    to_bool,
  )
  |> should.equal(ModifierType(Defaulted(PrimitiveType(Boolean), "hello")))
}

// ==== validate_modifier_default_value_recursive ====
// * ✅ Defaulted delegates to callback
// * ✅ Optional returns Error
pub fn validate_modifier_default_value_recursive_test() {
  let validate_inner = fn(_typ: AcceptedTypes, _val: String) { Ok(Nil) }

  types.validate_modifier_default_value_recursive(
    Defaulted(PrimitiveType(String), "hello"),
    "world",
    validate_inner,
  )
  |> should.equal(Ok(Nil))

  types.validate_modifier_default_value_recursive(
    Optional(PrimitiveType(String)),
    "world",
    validate_inner,
  )
  |> should.equal(Error(Nil))
}

// ===========================================================================
// RefinementTypes tests
// ===========================================================================

// ==== parse_refinement_type ====
// (extensive test cases - see comment headers)
pub fn parse_refinement_type_test() {
  [
    // ==== Happy Path (OneOf) ====
    #(
      "Integer { x | x in { 10, 20, 30 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Float)),
        set.from_list(["10.0", "20.0", "30.0"]),
      )),
    ),
    #(
      "String { x | x in { pizza, pasta, salad, tasty-food } }",
      Ok(OneOf(
        PrimitiveType(String),
        set.from_list(["pizza", "pasta", "salad", "tasty-food"]),
      )),
    ),
    #(
      "String { x | x in { 10 } }",
      Ok(OneOf(PrimitiveType(String), set.from_list(["10"]))),
    ),
    #(
      "Defaulted(String, default) { x | x in { a, b, c } }",
      Ok(OneOf(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        set.from_list(["a", "b", "c"]),
      )),
    ),
    #(
      "Defaulted(Integer, 10) { x | x in { 10, 20, 30 } }",
      Ok(OneOf(
        ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "10")),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Defaulted(Float, 1.5) { x | x in { 1.5, 2.5, 3.5 } }",
      Ok(OneOf(
        ModifierType(Defaulted(PrimitiveType(NumericType(Float)), "1.5")),
        set.from_list(["1.5", "2.5", "3.5"]),
      )),
    ),
    // OneOf flexible spacing
    #(
      "Integer { x | x in {10, 20, 30} }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x | x in {10, 20, 30 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x | x in { 10, 20, 30} }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "String { x | x in {pizza, pasta} }",
      Ok(OneOf(PrimitiveType(String), set.from_list(["pizza", "pasta"]))),
    ),
    // OneOf flexible spacing - around outer brace and pipe
    #(
      "Integer {x | x in { 10, 20, 30 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x| x in { 10, 20, 30 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x |x in { 10, 20, 30 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    #(
      "Integer { x | x in{ 10, 20, 30 } }",
      Ok(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
    ),
    // ==== Happy Path (InclusiveRange) ====
    #(
      "Integer { x | x in ( 0..100 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Integer { x | x in ( -100..-50 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "-100", "-50")),
    ),
    #(
      "Integer { x | x in ( -10..10 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "-10", "10")),
    ),
    #(
      "Float { x | x in ( 0.0..100.0 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Float)), "0.0", "100.0")),
    ),
    #(
      "Float { x | x in ( -100.5..-50.5 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Float)), "-100.5", "-50.5")),
    ),
    #(
      "Float { x | x in ( -10.5..10.5 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Float)), "-10.5", "10.5")),
    ),
    // InclusiveRange flexible spacing
    #(
      "Integer { x | x in (0..100) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Integer { x | x in (0..100 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Integer { x | x in ( 0..100) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Float { x | x in (0.0..100.0) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Float)), "0.0", "100.0")),
    ),
    // InclusiveRange flexible spacing - around outer brace and pipe
    #(
      "Integer {x | x in ( 0..100 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Integer { x| x in ( 0..100 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Integer { x |x in ( 0..100 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    #(
      "Integer { x | x in( 0..100 ) }",
      Ok(InclusiveRange(PrimitiveType(NumericType(Integer)), "0", "100")),
    ),
    // ==== Sad Path (OneOf) ====
    #("Boolean { x | x in { True, False } }", Error(Nil)),
    #("Integer { x | x in {  } }", Error(Nil)),
    #("Float { x | x in {  } }", Error(Nil)),
    #("String { x | x in {  } }", Error(Nil)),
    #("Integer { x | x in { 10.0 } }", Error(Nil)),
    #("Float { x | x in { pizza } }", Error(Nil)),
    #("Unknown { x | x in { 1, 2, 3 } }", Error(Nil)),
    #("List(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Dict(String, String) { x | x in { a, b, c } }", Error(Nil)),
    #("Optional(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Defaulted(Boolean, True) { x | x in { True, False } }", Error(Nil)),
    #("Defaulted(List(String), a) { x | x in { a, b, c } }", Error(Nil)),
    #("Defaulted(Dict(String, String), a) { x | x in { a, b } }", Error(Nil)),
    #("Defaulted(Optional(String), a) { x | x in { a, b, c } }", Error(Nil)),
    #("Integer { x | x in { 10, 20, 30 }", Error(Nil)),
    #("Integer { x | x in 10, 20, 30 } }", Error(Nil)),
    #("Integer x | x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { y | y in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x IN { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | xin { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x in { 10, 10, 20 } }", Error(Nil)),
    #("String { x | x in { pizza, pizza, pasta } }", Error(Nil)),
    // ==== Sad Path (InclusiveRange) ====
    #("String { x | x in ( a..z ) }", Error(Nil)),
    #("Integer { x | x in ( 0.5..100.5 ) }", Error(Nil)),
    #("Float { x | x in ( a..z ) }", Error(Nil)),
    #("Integer { x | x in ( ..100 ) }", Error(Nil)),
    #("Integer { x | x in ( 0.. ) }", Error(Nil)),
    #("Integer { x | x in ( 0..50..100 ) }", Error(Nil)),
    #("Integer { x | x in { 0..100 } }", Error(Nil)),
    #("Integer { x | x in ( 100..0 ) }", Error(Nil)),
    #("Float { x | x in ( 100.0..0.0 ) }", Error(Nil)),
    #("Defaulted(Integer, 50) { x | x in ( 0..100 ) }", Error(Nil)),
    #("Defaulted(Float, 1.5) { x | x in ( 0.0..100.0 ) }", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.parse_refinement_type(
      input,
      parse_primitive_or_defaulted,
      validate_string_literal,
    )
  })
}

// ==== refinement_type_to_string ====
pub fn refinement_type_to_string_test() {
  [
    #(
      RefinementType(OneOf(
        PrimitiveType(NumericType(Integer)),
        set.from_list(["10", "20", "30"]),
      )),
      "Integer { x | x in { 10, 20, 30 } }",
    ),
    #(
      RefinementType(OneOf(
        PrimitiveType(NumericType(Float)),
        set.from_list(["10.0", "20.0", "30.0"]),
      )),
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
    ),
    #(
      RefinementType(OneOf(
        PrimitiveType(String),
        set.from_list(["pasta", "pizza", "salad"]),
      )),
      "String { x | x in { pasta, pizza, salad } }",
    ),
    #(
      RefinementType(OneOf(
        ModifierType(Defaulted(PrimitiveType(String), "default")),
        set.from_list(["a", "b", "c"]),
      )),
      "Defaulted(String, default) { x | x in { a, b, c } }",
    ),
    #(
      RefinementType(OneOf(
        ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "10")),
        set.from_list(["10", "20", "30"]),
      )),
      "Defaulted(Integer, 10) { x | x in { 10, 20, 30 } }",
    ),
    // InclusiveRange(Integer) - basic range
    #(
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Integer)),
        "0",
        "100",
      )),
      "Integer { x | x in ( 0..100 ) }",
    ),
    // InclusiveRange(Integer) - negative range
    #(
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Integer)),
        "-100",
        "-50",
      )),
      "Integer { x | x in ( -100..-50 ) }",
    ),
    // InclusiveRange(Float) - basic range
    #(
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Float)),
        "0.0",
        "100.0",
      )),
      "Float { x | x in ( 0.0..100.0 ) }",
    ),
    // InclusiveRange(Float) - negative range
    #(
      RefinementType(InclusiveRange(
        PrimitiveType(NumericType(Float)),
        "-100.5",
        "-50.5",
      )),
      "Float { x | x in ( -100.5..-50.5 ) }",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    types.accepted_type_to_string(input)
  })
}

// ==== validate_refinement_value ====
pub fn validate_refinement_value_test() {
  [
    // Integer happy path - value in set
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.IntValue(10),
      ),
      True,
    ),
    // Integer sad path - value not in set
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.IntValue(99),
      ),
      False,
    ),
    // String happy path - value in set
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(String),
          set.from_list(["pizza", "pasta", "salad"]),
        )),
        value.StringValue("pizza"),
      ),
      True,
    ),
    // String sad path - value not in set
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(String),
          set.from_list(["pizza", "pasta", "salad"]),
        )),
        value.StringValue("burger"),
      ),
      False,
    ),
    // InclusiveRange(Integer) happy path - value in range
    #(
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.IntValue(50),
      ),
      True,
    ),
    // InclusiveRange(Integer) sad path - value below range
    #(
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.IntValue(-1),
      ),
      False,
    ),
    // InclusiveRange(Float) happy path - value in range
    #(
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Float)),
          "0.0",
          "100.0",
        )),
        value.FloatValue(50.5),
      ),
      True,
    ),
    // InclusiveRange(Float) sad path - value above range
    #(
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Float)),
          "0.0",
          "100.0",
        )),
        value.FloatValue(100.1),
      ),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_refinement_to_string ====
pub fn resolve_refinement_to_string_test() {
  let resolve_string = fn(x: String) { x }
  let resolve_list = fn(l) { string.join(l, ",") }

  [
    // Integer happy path
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.IntValue(10),
      ),
      Ok("10"),
    ),
    // String happy path
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(String),
          set.from_list(["pasta", "pizza", "salad"]),
        )),
        value.StringValue("pizza"),
      ),
      Ok("pizza"),
    ),
    // Decode error - wrong type
    #(
      #(
        RefinementType(OneOf(
          PrimitiveType(NumericType(Integer)),
          set.from_list(["10", "20", "30"]),
        )),
        value.StringValue("not an integer"),
      ),
      Error("Unable to resolve OneOf refinement type value."),
    ),
    // InclusiveRange(Integer) happy path
    #(
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.IntValue(50),
      ),
      Ok("50"),
    ),
    // InclusiveRange(Integer) decode error
    #(
      #(
        RefinementType(InclusiveRange(
          PrimitiveType(NumericType(Integer)),
          "0",
          "100",
        )),
        value.StringValue("not an integer"),
      ),
      Error("Unable to resolve InclusiveRange refinement type value."),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, resolve_string, resolve_list)
  })
}

// ==== refinement_all_type_metas ====
// * ✅ returns entries for OneOf and InclusiveRange
pub fn refinement_all_type_metas_test() {
  let metas = types.all_type_metas()
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "OneOf") |> should.be_true()
  list.contains(names, "InclusiveRange") |> should.be_true()
}

// ==== refinement_try_each_inner ====
// * ✅ OneOf calls f with inner type
// * ✅ InclusiveRange calls f with inner type
// * ✅ Error propagation
pub fn refinement_try_each_inner_test() {
  let always_ok = fn(_: AcceptedTypes) { Ok(Nil) }
  let string_type = PrimitiveType(String)

  types.try_each_inner(
    RefinementType(OneOf(string_type, set.from_list(["a"]))),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  types.try_each_inner(
    RefinementType(InclusiveRange(
      PrimitiveType(NumericType(Integer)),
      "0",
      "100",
    )),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  let always_err = fn(_: AcceptedTypes) { Error("fail") }
  types.try_each_inner(
    RefinementType(OneOf(string_type, set.from_list(["a"]))),
    always_err,
  )
  |> should.equal(Error("fail"))
}

// ==== refinement_map_inner ====
// * ✅ OneOf transforms inner, preserves set
// * ✅ InclusiveRange transforms inner, preserves bounds
pub fn refinement_map_inner_test() {
  let string_type = PrimitiveType(String)
  let bool_type = PrimitiveType(Boolean)
  let to_bool = fn(_: AcceptedTypes) { bool_type }

  types.map_inner(
    RefinementType(OneOf(string_type, set.from_list(["a", "b"]))),
    to_bool,
  )
  |> should.equal(RefinementType(OneOf(bool_type, set.from_list(["a", "b"]))))

  let int_type = PrimitiveType(NumericType(Integer))
  types.map_inner(RefinementType(InclusiveRange(int_type, "0", "100")), to_bool)
  |> should.equal(RefinementType(InclusiveRange(bool_type, "0", "100")))
}

// ==== validate_refinement_default_value ====
// * ✅ OneOf - value in set -> Ok
// * ✅ OneOf - value not in set -> Error
// * ✅ InclusiveRange - value in range -> Ok
// * ✅ InclusiveRange - value out of range -> Error
pub fn validate_refinement_default_value_test() {
  let string_type = PrimitiveType(String)
  let int_type = PrimitiveType(NumericType(Integer))
  let validate_inner = fn(typ: AcceptedTypes, val: String) {
    case typ {
      PrimitiveType(String) -> Ok(Nil)
      PrimitiveType(NumericType(numeric)) ->
        types.validate_numeric_default_value(numeric, val)
      _ -> Error(Nil)
    }
  }

  // OneOf - value in set
  types.validate_refinement_default_value(
    OneOf(string_type, set.from_list(["a", "b", "c"])),
    "b",
    validate_inner,
  )
  |> should.equal(Ok(Nil))

  // OneOf - value not in set
  types.validate_refinement_default_value(
    OneOf(string_type, set.from_list(["a", "b", "c"])),
    "z",
    validate_inner,
  )
  |> should.equal(Error(Nil))

  // InclusiveRange - value in range
  types.validate_refinement_default_value(
    InclusiveRange(int_type, "0", "100"),
    "50",
    validate_inner,
  )
  |> should.equal(Ok(Nil))

  // InclusiveRange - value out of range
  types.validate_refinement_default_value(
    InclusiveRange(int_type, "0", "100"),
    "200",
    validate_inner,
  )
  |> should.equal(Error(Nil))
}

// ===========================================================================
// AcceptedTypes (integration) tests
// ===========================================================================

// ==== accepted_type_to_string ====
// Integration test: verifies dispatch across type hierarchy
// * ✅ Primitive -> delegates to primitive_types
// * ✅ Collection -> delegates to collection_types
// * ✅ Modifier wrapping Collection -> nested delegation
pub fn accepted_type_to_string_test() {
  [
    // Primitive dispatch
    #(PrimitiveType(String), "String"),
    // Collection dispatch
    #(CollectionType(List(PrimitiveType(String))), "List(String)"),
    // Modifier wrapping Collection - nested dispatch
    #(
      ModifierType(
        Optional(
          CollectionType(Dict(
            PrimitiveType(String),
            PrimitiveType(NumericType(Integer)),
          )),
        ),
      ),
      "Optional(Dict(String, Integer))",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(types.accepted_type_to_string)
}

// ==== parse_accepted_type ====
// Integration test: verifies parsing dispatch and composition rules
pub fn parse_accepted_type_test() {
  [
    // Composite type - modifier wrapping collection
    #(
      "Optional(List(String))",
      Ok(ModifierType(Optional(CollectionType(List(PrimitiveType(String)))))),
    ),
    // Nested collections - now allowed
    #(
      "List(List(String))",
      Ok(CollectionType(List(CollectionType(List(PrimitiveType(String)))))),
    ),
    #(
      "Dict(String, List(String))",
      Ok(
        CollectionType(Dict(
          PrimitiveType(String),
          CollectionType(List(PrimitiveType(String))),
        )),
      ),
    ),
    // Invalid - nested modifiers not allowed
    #("Optional(Optional(String))", Error(Nil)),
    #("Defaulted(Optional(String), default)", Error(Nil)),
    // Invalid - Defaulted only allows primitives, refinements, or collections
    #("Defaulted(List(String), default)", Error(Nil)),
    // Defaulted with refinement inner type (what happens after type alias resolution)
    #(
      "Defaulted(String { x | x in { demo, development, production } }, production)",
      Ok(
        ModifierType(Defaulted(
          RefinementType(OneOf(
            PrimitiveType(String),
            set.from_list(["demo", "development", "production"]),
          )),
          "production",
        )),
      ),
    ),
    // Invalid - Defaulted with refinement but default not in set
    #(
      "Defaulted(String { x | x in { demo, production } }, invalid)",
      Error(Nil),
    ),
    // Refinement type with Defaulted inner type
    #(
      "Defaulted(String, production) { x | x in { production } }",
      Ok(
        RefinementType(OneOf(
          ModifierType(Defaulted(PrimitiveType(String), "production")),
          set.from_list(["production"]),
        )),
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(types.parse_accepted_type)
}

// ==== validate_value (integration) ====
pub fn validate_value_test() {
  [
    // Primitive dispatch
    #(#(PrimitiveType(String), value.StringValue("hello")), True),
    // Collection dispatch
    #(
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.ListValue([value.IntValue(1), value.IntValue(2)]),
      ),
      True,
    ),
    // Modifier dispatch
    #(#(ModifierType(Optional(PrimitiveType(String))), value.NilValue), True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

fn result_to_ok_string_from_string_error(
  result: Result(String, String),
) -> Result(String, Nil) {
  case result {
    Ok(s) -> Ok(s)
    Error(_) -> Error(Nil)
  }
}

// ==== resolve_to_string (integration) ====
pub fn resolve_to_string_test() {
  let string_resolver = fn(s) { "resolved:" <> s }
  let list_resolver = fn(l) { "list:[" <> string.join(l, ",") <> "]" }

  [
    // Primitive dispatch
    #(
      #(PrimitiveType(String), value.StringValue("hello")),
      Ok("resolved:hello"),
    ),
    // Collection dispatch
    #(
      #(
        CollectionType(List(PrimitiveType(NumericType(Integer)))),
        value.ListValue([value.IntValue(1), value.IntValue(2)]),
      ),
      Ok("list:[1,2]"),
    ),
    // Modifier dispatch - Optional with value
    #(
      #(
        ModifierType(Optional(PrimitiveType(String))),
        value.StringValue("present"),
      ),
      Ok("resolved:present"),
    ),
    // Modifier dispatch - Defaulted with None uses default
    #(
      #(
        ModifierType(Defaulted(PrimitiveType(NumericType(Integer)), "99")),
        value.NilValue,
      ),
      Ok("resolved:99"),
    ),
    // Refinement dispatch - OneOf(Defaulted(String)) with value provided
    #(
      #(
        RefinementType(OneOf(
          ModifierType(Defaulted(PrimitiveType(String), "production")),
          set.from_list(["production", "staging"]),
        )),
        value.StringValue("staging"),
      ),
      Ok("resolved:staging"),
    ),
    // Refinement dispatch - OneOf(Defaulted(String)) with None uses default
    #(
      #(
        RefinementType(OneOf(
          ModifierType(Defaulted(PrimitiveType(String), "production")),
          set.from_list(["production", "staging"]),
        )),
        value.NilValue,
      ),
      Ok("resolved:production"),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    types.resolve_to_string(typ, value, string_resolver, list_resolver)
    |> result_to_ok_string_from_string_error
  })
}

// ==== get_numeric_type ====
// * ✅ Integer primitive -> Integer
// * ✅ Float primitive -> Float
// * ✅ Non-numeric types fall back to Integer
pub fn get_numeric_type_test() {
  [
    #(PrimitiveType(NumericType(Integer)), Integer),
    #(PrimitiveType(NumericType(Float)), Float),
    // Fallback cases
    #(PrimitiveType(String), Integer),
    #(PrimitiveType(Boolean), Integer),
    #(CollectionType(List(PrimitiveType(String))), Integer),
  ]
  |> test_helpers.array_based_test_executor_1(types.get_numeric_type)
}

// ==== is_optional_or_defaulted ====
// * ✅ Optional -> True
// * ✅ Defaulted -> True
// * ✅ OneOf wrapping Optional -> True
// * ✅ Plain primitive -> False
// * ✅ Collection -> False
pub fn is_optional_or_defaulted_test() {
  [
    #(ModifierType(Optional(PrimitiveType(String))), True),
    #(ModifierType(Defaulted(PrimitiveType(String), "hello")), True),
    #(
      RefinementType(OneOf(
        ModifierType(Optional(PrimitiveType(String))),
        set.from_list(["a", "b"]),
      )),
      True,
    ),
    #(PrimitiveType(String), False),
    #(CollectionType(List(PrimitiveType(String))), False),
  ]
  |> test_helpers.array_based_test_executor_1(types.is_optional_or_defaulted)
}

// ==== all_type_metas ====
// * ✅ returns non-empty list with entries from all 4 categories
pub fn all_type_metas_test() {
  let metas = types.all_type_metas()
  // Should have entries from primitives, collections, modifiers, and refinements
  { metas != [] } |> should.be_true()

  // Verify it includes entries from each category by checking known names
  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Optional") |> should.be_true()
  list.contains(names, "OneOf") |> should.be_true()
}

// ==== completable_type_metas ====
// * ✅ includes primitives, collections, and modifiers
// * ✅ excludes refinement types (OneOf, InclusiveRange)
pub fn completable_type_metas_test() {
  let metas = types.completable_type_metas()
  let names = list.map(metas, fn(m) { m.name })

  // Includes completable types
  list.contains(names, "Boolean") |> should.be_true()
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Optional") |> should.be_true()

  // Excludes refinement types — they are not standalone types
  list.contains(names, "OneOf") |> should.be_false()
  list.contains(names, "InclusiveRange") |> should.be_false()
}

// ==== try_each_inner ====
pub fn try_each_inner_test() {
  let always_ok = fn(_) { Ok(Nil) }

  // PrimitiveType calls f with self
  types.try_each_inner(PrimitiveType(String), always_ok)
  |> should.equal(Ok(Nil))

  // CollectionType - List calls f once
  types.try_each_inner(CollectionType(List(PrimitiveType(String))), always_ok)
  |> should.equal(Ok(Nil))

  // ModifierType - Optional calls f with inner
  types.try_each_inner(ModifierType(Optional(PrimitiveType(String))), always_ok)
  |> should.equal(Ok(Nil))

  // RefinementType - OneOf calls f with inner
  types.try_each_inner(
    RefinementType(OneOf(PrimitiveType(String), set.from_list(["a"]))),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // Error propagation - f returns error
  let always_err = fn(_) { Error("fail") }
  types.try_each_inner(PrimitiveType(String), always_err)
  |> should.equal(Error("fail"))
}

// ==== map_inner ====
pub fn map_inner_test() {
  let identity = fn(t) { t }

  // PrimitiveType -> f is called on self
  types.map_inner(PrimitiveType(String), identity)
  |> should.equal(PrimitiveType(String))

  // CollectionType List -> inner is transformed
  let to_bool = fn(_) { PrimitiveType(Boolean) }
  types.map_inner(CollectionType(List(PrimitiveType(String))), to_bool)
  |> should.equal(CollectionType(List(PrimitiveType(Boolean))))

  // ModifierType Optional -> inner is transformed
  types.map_inner(ModifierType(Optional(PrimitiveType(String))), to_bool)
  |> should.equal(ModifierType(Optional(PrimitiveType(Boolean))))

  // RefinementType OneOf -> inner is transformed, set preserved
  types.map_inner(
    RefinementType(OneOf(PrimitiveType(String), set.from_list(["a", "b"]))),
    to_bool,
  )
  |> should.equal(
    RefinementType(OneOf(PrimitiveType(Boolean), set.from_list(["a", "b"]))),
  )
}

// ===========================================================================
// RecordType tests
// ===========================================================================

// ==== record_type_to_string ====
// * ✅ formats fields alphabetically
// * ✅ handles nested types
pub fn record_type_to_string_test() {
  // Simple record
  RecordType(
    dict.from_list([
      #("numerator", PrimitiveType(String)),
      #("denominator", PrimitiveType(String)),
    ]),
  )
  |> types.accepted_type_to_string
  |> should.equal("{ denominator: String, numerator: String }")

  // Record with mixed types
  RecordType(
    dict.from_list([
      #("name", PrimitiveType(String)),
      #("count", PrimitiveType(NumericType(Integer))),
    ]),
  )
  |> types.accepted_type_to_string
  |> should.equal("{ count: Integer, name: String }")
}

// ==== validate_record_value ====
// ==== Happy Path ====
// * ✅ all fields present and valid
// * ✅ optional field absent
// ==== Sad Path ====
// * ✅ missing required field
// * ✅ extra field rejected
// * ✅ wrong type in field
// * ✅ not a dict value
pub fn validate_record_value_test() {
  let schema =
    RecordType(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("count", PrimitiveType(NumericType(Integer))),
      ]),
    )

  // Happy: all fields present
  let val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("count", value.IntValue(42)),
      ]),
    )
  types.validate_value(schema, val) |> should.be_ok

  // Sad: missing required field
  let missing_val =
    value.DictValue(dict.from_list([#("name", value.StringValue("test"))]))
  types.validate_value(schema, missing_val) |> should.be_error

  // Sad: extra field
  let extra_val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("count", value.IntValue(42)),
        #("extra", value.StringValue("oops")),
      ]),
    )
  types.validate_value(schema, extra_val) |> should.be_error

  // Sad: wrong type
  let wrong_val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("count", value.StringValue("not_an_int")),
      ]),
    )
  types.validate_value(schema, wrong_val) |> should.be_error

  // Sad: not a dict
  types.validate_value(schema, value.StringValue("nope")) |> should.be_error
}

// ==== validate_record_value (optional fields) ====
// * ✅ optional field can be absent
pub fn validate_record_value_optional_test() {
  let schema =
    RecordType(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #("label", ModifierType(Optional(PrimitiveType(String)))),
      ]),
    )

  // Only required field present
  let val =
    value.DictValue(dict.from_list([#("name", value.StringValue("test"))]))
  types.validate_value(schema, val) |> should.be_ok

  // Both fields present
  let full_val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #("label", value.StringValue("my-label")),
      ]),
    )
  types.validate_value(schema, full_val) |> should.be_ok
}

// ==== validate_record_value (nested) ====
// * ✅ nested record validates recursively
pub fn validate_record_value_nested_test() {
  let schema =
    RecordType(
      dict.from_list([
        #("name", PrimitiveType(String)),
        #(
          "metrics",
          RecordType(
            dict.from_list([
              #("latency", PrimitiveType(NumericType(Integer))),
              #("errors", PrimitiveType(NumericType(Integer))),
            ]),
          ),
        ),
      ]),
    )

  let val =
    value.DictValue(
      dict.from_list([
        #("name", value.StringValue("test")),
        #(
          "metrics",
          value.DictValue(
            dict.from_list([
              #("latency", value.IntValue(100)),
              #("errors", value.IntValue(5)),
            ]),
          ),
        ),
      ]),
    )
  types.validate_value(schema, val) |> should.be_ok
}

// ==== record try_each_inner ====
// * ✅ visits all field types
pub fn record_try_each_inner_test() {
  let record =
    RecordType(
      dict.from_list([
        #("a", PrimitiveType(String)),
        #("b", PrimitiveType(NumericType(Integer))),
      ]),
    )
  types.try_each_inner(record, fn(_) { Ok(Nil) }) |> should.be_ok
}

// ==== record map_inner ====
// * ✅ transforms all field types
pub fn record_map_inner_test() {
  let to_bool = fn(_) { PrimitiveType(Boolean) }
  types.map_inner(
    RecordType(
      dict.from_list([
        #("a", PrimitiveType(String)),
        #("b", PrimitiveType(NumericType(Integer))),
      ]),
    ),
    to_bool,
  )
  |> should.equal(
    RecordType(
      dict.from_list([
        #("a", PrimitiveType(Boolean)),
        #("b", PrimitiveType(Boolean)),
      ]),
    ),
  )
}

// ==== record resolve_to_string ====
// * ✅ record types cannot be template variables
pub fn record_resolve_to_string_test() {
  let record = RecordType(dict.from_list([#("a", PrimitiveType(String))]))
  types.resolve_to_string(record, value.StringValue("x"), fn(s) { s }, fn(l) {
    string.join(l, ",")
  })
  |> should.be_error
}

// ==== record is_optional_or_defaulted ====
// * ✅ record is not optional/defaulted
pub fn record_is_optional_or_defaulted_test() {
  RecordType(dict.from_list([#("a", PrimitiveType(String))]))
  |> types.is_optional_or_defaulted
  |> should.be_false
}

// ===========================================================================
// Test helpers (private to this test module)
// ===========================================================================

/// Parser for refinement-compatible types (Integer, Float, String, or Defaulted with those).
fn parse_primitive_or_defaulted(raw: String) -> Result(AcceptedTypes, Nil) {
  case parse_refinement_compatible_primitive(raw) {
    Ok(prim) -> Ok(PrimitiveType(prim))
    Error(_) ->
      case
        types.parse_modifier_type(
          raw,
          parse_refinement_compatible,
          validate_refinement_compatible_default,
        )
      {
        Ok(modifier) -> Ok(ModifierType(modifier))
        Error(_) -> Error(Nil)
      }
  }
}

/// Parser for refinement-compatible primitives only (Integer, Float, String - not Boolean).
fn parse_refinement_compatible(raw: String) -> Result(AcceptedTypes, Nil) {
  parse_refinement_compatible_primitive(raw)
  |> result.map(PrimitiveType)
}

/// Parses only Integer, Float, or String primitives (excludes Boolean).
fn parse_refinement_compatible_primitive(
  raw: String,
) -> Result(PrimitiveTypes, Nil) {
  case raw {
    "String" -> Ok(String)
    "Integer" -> Ok(NumericType(Integer))
    "Float" -> Ok(NumericType(Float))
    _ -> Error(Nil)
  }
}

/// Validates a string literal value is valid for an AcceptedTypes.
fn validate_string_literal(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    PrimitiveType(primitive) ->
      types.validate_primitive_default_value(primitive, value)
    ModifierType(Defaulted(inner, _)) -> validate_string_literal(inner, value)
    _ -> Error(Nil)
  }
}

/// Validates a default value for refinement-compatible primitives only.
fn validate_refinement_compatible_default(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    PrimitiveType(String) -> Ok(Nil)
    PrimitiveType(NumericType(numeric)) ->
      types.validate_numeric_default_value(numeric, value)
    _ -> Error(Nil)
  }
}
