import caffeine_lang/common/collection_types
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/string
import gleeunit/should
import test_helpers

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
    #("List(String)", Ok(collection_types.List("String"))),
    #("List(Integer)", Ok(collection_types.List("Integer"))),
    #("List(Float)", Ok(collection_types.List("Float"))),
    #("List(Boolean)", Ok(collection_types.List("Boolean"))),
    #("Dict(String, String)", Ok(collection_types.Dict("String", "String"))),
    #("Dict(String, Integer)", Ok(collection_types.Dict("String", "Integer"))),
    #("Dict(Integer, String)", Ok(collection_types.Dict("Integer", "String"))),
    // Nested collections
    #(
      "Dict(String, List(Integer))",
      Ok(collection_types.Dict("String", "List(Integer)")),
    ),
    #(
      "Dict(String, Dict(String, Integer))",
      Ok(collection_types.Dict("String", "Dict(String, Integer)")),
    ),
    #("List(List(String))", Ok(collection_types.List("List(String)"))),
    // Sad paths
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
// * ✅ Dict validates dict with inner types (both keys AND values)
// * ✅ Dict rejects non-dict
// * ✅ Dict key validation - rejects invalid keys
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
      #(
        collection_types.Dict("String", "Integer"),
        dynamic.string("not a dict"),
      ),
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

  // Dict key validation test - validates that keys ARE validated
  // Validator that only accepts "valid_key" as a key type
  let validate_key_selective = fn(typ: String, value: dynamic.Dynamic) {
    case typ {
      "ValidKeyType" -> {
        case decode.run(value, decode.string) {
          Ok("valid_key") -> Ok(value)
          Ok("another_valid") -> Ok(value)
          _ -> Error([decode.DecodeError("InvalidKey", "String", [])])
        }
      }
      _ -> Ok(value)
    }
  }

  [
    // Dict with valid key passes
    #(
      #(
        collection_types.Dict("ValidKeyType", "String"),
        dynamic.properties([#(dynamic.string("valid_key"), dynamic.string("v"))]),
      ),
      True,
    ),
    // Dict with invalid key fails - key "bad_key" not in allowed set
    #(
      #(
        collection_types.Dict("ValidKeyType", "String"),
        dynamic.properties([#(dynamic.string("bad_key"), dynamic.string("v"))]),
      ),
      False,
    ),
    // Dict with multiple keys - all must be valid
    #(
      #(
        collection_types.Dict("ValidKeyType", "String"),
        dynamic.properties([
          #(dynamic.string("valid_key"), dynamic.string("v1")),
          #(dynamic.string("another_valid"), dynamic.string("v2")),
        ]),
      ),
      True,
    ),
    // Dict with one invalid key among valid ones - fails
    #(
      #(
        collection_types.Dict("ValidKeyType", "String"),
        dynamic.properties([
          #(dynamic.string("valid_key"), dynamic.string("v1")),
          #(dynamic.string("invalid_key"), dynamic.string("v2")),
        ]),
      ),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case collection_types.validate_value(typ, value, validate_key_selective) {
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

// ==== all_type_metas ====
// * ✅ returns 2 entries (List, Dict)
pub fn all_type_metas_test() {
  let metas = collection_types.all_type_metas()
  list.length(metas) |> should.equal(2)

  let names = list.map(metas, fn(m) { m.name })
  list.contains(names, "List") |> should.be_true()
  list.contains(names, "Dict") |> should.be_true()
}

// ==== try_each_inner ====
// * ✅ List calls f once with inner type
// * ✅ Dict calls f twice (key and value)
// * ✅ Error propagation from first call in Dict
pub fn try_each_inner_test() {
  let always_ok = fn(_: String) { Ok(Nil) }

  // List calls f once
  collection_types.try_each_inner(collection_types.List("String"), always_ok)
  |> should.equal(Ok(Nil))

  // Dict calls f twice
  collection_types.try_each_inner(
    collection_types.Dict("String", "Integer"),
    always_ok,
  )
  |> should.equal(Ok(Nil))

  // Error propagation
  let fail_on = fn(typ: String) {
    case typ {
      "Integer" -> Error("bad type")
      _ -> Ok(Nil)
    }
  }
  collection_types.try_each_inner(
    collection_types.Dict("String", "Integer"),
    fail_on,
  )
  |> should.equal(Error("bad type"))

  // Error on key stops early
  collection_types.try_each_inner(
    collection_types.Dict("Integer", "String"),
    fail_on,
  )
  |> should.equal(Error("bad type"))
}

// ==== map_inner ====
// * ✅ List transforms inner type
// * ✅ Dict transforms both key and value types
pub fn map_inner_test() {
  let to_upper = fn(s: String) { string.uppercase(s) }

  collection_types.map_inner(collection_types.List("string"), to_upper)
  |> should.equal(collection_types.List("STRING"))

  collection_types.map_inner(
    collection_types.Dict("string", "integer"),
    to_upper,
  )
  |> should.equal(collection_types.Dict("STRING", "INTEGER"))
}
