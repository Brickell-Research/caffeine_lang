import caffeine_lang/common/collection_types
import gleam/dynamic
import gleam/dynamic/decode
import gleam/string
import test_helpers

// ==== parse_collection_type ====
// ==== Happy Path ====
// * ✅ List(String)
// * ✅ List(Integer)
// * ✅ Dict(String, String)
// * ✅ Dict(String, Integer)
// ==== Sad Path ====
// * ✅ Unknown type
// * ✅ Empty string
// * ✅ List without parens
// * ✅ List with invalid inner type
pub fn parse_collection_type_test() {
  // Helper to parse inner types (simulating primitive-only parsing)
  let parse_inner = fn(raw: String) {
    case raw {
      "String" -> Ok("String")
      "Integer" -> Ok("Integer")
      "Float" -> Ok("Float")
      "Boolean" -> Ok("Boolean")
      _ -> Error(Nil)
    }
  }

  [
    #("List(String)", Ok(collection_types.List("String"))),
    #("List(Integer)", Ok(collection_types.List("Integer"))),
    #("List(Float)", Ok(collection_types.List("Float"))),
    #("List(Boolean)", Ok(collection_types.List("Boolean"))),
    #("Dict(String, String)", Ok(collection_types.Dict("String", "String"))),
    #("Dict(String, Integer)", Ok(collection_types.Dict("String", "Integer"))),
    #("Dict(Integer, String)", Ok(collection_types.Dict("Integer", "String"))),
    #("Unknown", Error(Nil)),
    #("", Error(Nil)),
    #("List", Error(Nil)),
    #("List(Unknown)", Error(Nil)),
    #("Dict(Unknown, String)", Error(Nil)),
    #("Dict(String, Unknown)", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    collection_types.parse_collection_type(input, parse_inner)
  })
}

// ==== collection_type_to_string ====
// * ✅ List(T) -> "List(T)"
// * ✅ Dict(K, V) -> "Dict(K, V)"
pub fn collection_type_to_string_test() {
  // Identity function for inner type string conversion
  let inner_to_string = fn(x: String) { x }

  [
    #(collection_types.List("String"), "List(String)"),
    #(collection_types.List("Integer"), "List(Integer)"),
    #(collection_types.Dict("String", "String"), "Dict(String, String)"),
    #(collection_types.Dict("String", "Integer"), "Dict(String, Integer)"),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    collection_types.collection_type_to_string(input, inner_to_string)
  })
}

// ==== validate_value ====
// * ✅ List validates list of inner type
// * ✅ List rejects non-list
// * ✅ Dict validates dict with inner types
// * ✅ Dict rejects non-dict
pub fn validate_value_test() {
  // Simple validator that always succeeds (simulates inner type validation)
  let validate_inner = fn(_typ: String, value: dynamic.Dynamic) { Ok(value) }

  [
    // List happy path
    #(
      #(
        collection_types.List("Integer"),
        dynamic.list([dynamic.int(1), dynamic.int(2)]),
      ),
      True,
    ),
    // List sad path - not a list
    #(#(collection_types.List("Integer"), dynamic.string("not a list")), False),
    // Dict happy path
    #(
      #(
        collection_types.Dict("String", "Integer"),
        dynamic.properties([#(dynamic.string("a"), dynamic.int(1))]),
      ),
      True,
    ),
    // Dict sad path - not a dict
    #(
      #(collection_types.Dict("String", "Integer"), dynamic.string("not a dict")),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case collection_types.validate_value(typ, value, validate_inner) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_to_string ====
// * ✅ List resolves with list resolver
// * ✅ Dict returns error (unsupported)
pub fn resolve_to_string_test() {
  let decode_inner = fn(_typ: String) { decode.string }
  let list_resolver = fn(l) { "list:[" <> string.join(l, ",") <> "]" }
  let type_to_string = fn(c) {
    collection_types.collection_type_to_string(c, fn(x) { x })
  }

  [
    // List happy path
    #(
      #(
        collection_types.List("String"),
        dynamic.list([dynamic.string("a"), dynamic.string("b")]),
      ),
      Ok("list:[a,b]"),
    ),
    // Dict returns error
    #(
      #(collection_types.Dict("String", "String"), dynamic.list([])),
      Error(
        "Unsupported templatized variable type: Dict(String, String). Dict support is pending, open an issue if this is a desired use case.",
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    collection_types.resolve_to_string(
      typ,
      value,
      decode_inner,
      list_resolver,
      type_to_string,
    )
  })
}
