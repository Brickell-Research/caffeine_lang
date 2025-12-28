import caffeine_lang/common/refinement_types
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/result
import gleam/set
import test_helpers

// ==== parse_refinement_type ====
// ==== Happy Path ====
// * ✅ Refinement(Integer)
// * ✅ Refinement(Float)
// * ✅ Refinement(String)
// ==== Sad Path ====
// * ✅ Refinement(Integer) - with empty set
// * ✅ Refinement(Float) - with empty set
// * ✅ Refinement(String) - with empty set
// * ✅ Refinement(Integer) - with invalid types in set
// * ✅ Refinement(Float) - with invalid types in set
// * ✅ Refinement(String) - with invalid types in set
// * ✅ Refinement(Unknown) - invalid inner type
// * ✅ Refinement(Boolean)
// * ✅ Refinement(List(String))
// * ✅ Refinement(Dict(String, String))
// * ✅ Refinement(Optional(String))
// * ✅ Refinement(Defaulted(String, "default"))
// * ✅ Malformed syntax - missing outer closing bracket
// * ✅ Malformed syntax - missing inner opening bracket
// * ✅ Malformed syntax - missing outer opening bracket
// * ✅ Malformed syntax - wrong variable name (y instead of x)
// * ✅ Malformed syntax - wrong case (IN instead of in)
// * ✅ Malformed syntax - missing space after opening bracket
// * ✅ Malformed syntax - missing space before pipe
// * ✅ Malformed syntax - missing space after pipe
// * ✅ Malformed syntax - missing space after "x"
// * ✅ Malformed syntax - missing space before inner opening bracket
// * ✅ Malformed syntax - missing space after inner opening bracket
pub fn parse_refinement_type_test() {
  let parse_inner = fn(raw: String) {
    case raw {
      "String" -> Ok("String")
      "Integer" -> Ok("Integer")
      "Float" -> Ok("Float")
      "Boolean" -> Ok("Boolean")
      _ -> Error(Nil)
    }
  }

  let validate_set_value = fn(typ: String, value: String) {
    case typ {
      "String" -> Ok(Nil)
      "Integer" ->
        int.parse(value)
        |> result.replace(Nil)
        |> result.replace_error(Nil)
      "Float" ->
        float.parse(value)
        |> result.replace(Nil)
        |> result.replace_error(Nil)
      _ -> Error(Nil)
    }
  }

  [
    #(
      "Integer { x | x in { 10, 20, 30 } }",
      Ok(refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"]))),
    ),
    #(
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
      Ok(refinement_types.OneOf(
        "Float",
        set.from_list(["10.0", "20.0", "30.0"]),
      )),
    ),
    #(
      "String { x | x in { pizza, pasta, salad } }",
      Ok(refinement_types.OneOf(
        "String",
        set.from_list(["pizza", "pasta", "salad"]),
      )),
    ),
    #("Boolean { x | x in { True, False } }", Error(Nil)),
    // Sad path - empty set (parser produces set with empty string element)
    #("Integer { x | x in {  } }", Error(Nil)),
    #("Float { x | x in {  } }", Error(Nil)),
    #("String { x | x in {  } }", Error(Nil)),
    // Sad path - invalid types in set
    #("Integer { x | x in { 10.0 } }", Error(Nil)),
    #("Float { x | x in { pizza } }", Error(Nil)),
    #("String { x | x in { 10 } }", Ok(refinement_types.OneOf("String", set.from_list(["10"])))),
    // Sad path - invalid inner type (parse_inner returns Error)
    #("Unknown { x | x in { 1, 2, 3 } }", Error(Nil)),
    // Sad path - List/Dict/Optional/Defaulted not supported
    #("List(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Dict(String, String) { x | x in { a, b, c } }", Error(Nil)),
    #("Optional(String) { x | x in { a, b, c } }", Error(Nil)),
    #("Defaulted(String, default) { x | x in { a, b, c } }", Error(Nil)),
    // Sad path - malformed syntax / missing brackets
    #("Integer { x | x in { 10, 20, 30 }", Error(Nil)),
    #("Integer { x | x in 10, 20, 30 } }", Error(Nil)),
    #("Integer x | x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { y | y in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x IN { 10, 20, 30 } }", Error(Nil)),
    #("Integer {x | x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x| x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x |x in { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | xin { 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x in{ 10, 20, 30 } }", Error(Nil)),
    #("Integer { x | x in {10, 20, 30 } }", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    refinement_types.parse_refinement_type(input, parse_inner, validate_set_value)
  })
}

// ==== refinement_type_to_string ====
// Since we only support Integer, Float, and String initially, this is a fairly small set of tests.
// * ✅ OneOf(T, {}) -> "T {x | x in {...} }"
//   * ✅ Integer
//   * ✅ Float
//   * ✅ String
pub fn refinement_type_to_string_test() {
  [
    #(
      refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"])),
      "Integer { x | x in { 10, 20, 30 } }",
    ),
    #(
      refinement_types.OneOf("Float", set.from_list(["10.0", "20.0", "30.0"])),
      "Float { x | x in { 10.0, 20.0, 30.0 } }",
    ),
    #(
      refinement_types.OneOf(
        "String",
        set.from_list(["pasta", "pizza", "salad"]),
      ),
      "String { x | x in { pasta, pizza, salad } }",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    refinement_types.refinement_type_to_string(input, fn(x: String) { x })
  })
}

// ==== validate_value ====
// * ✅ OneOf(Integer) - happy + sad
// * ✅ OneOf(Float) - happy + sad
// * ✅ OneOf(String) - happy + sad
// * ✅ OneOf - wrong type entirely -> Error
pub fn validate_value_test() {
  let decode_inner = fn(typ: String) {
    case typ {
      "Integer" -> {
        use val <- decode.then(decode.int)
        decode.success(int.to_string(val))
      }
      "Float" -> {
        use val <- decode.then(decode.float)
        decode.success(float.to_string(val))
      }
      "String" -> decode.string
      _ -> decode.failure("", "Unknown type")
    }
  }

  [
    // Integer happy path - value in set
    #(
      #(
        refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"])),
        dynamic.int(10),
      ),
      True,
    ),
    // Integer sad path - value not in set
    #(
      #(
        refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"])),
        dynamic.int(99),
      ),
      False,
    ),
    // Float happy path - value in set
    #(
      #(
        refinement_types.OneOf("Float", set.from_list(["1.5", "2.5", "3.5"])),
        dynamic.float(1.5),
      ),
      True,
    ),
    // Float sad path - value not in set
    #(
      #(
        refinement_types.OneOf("Float", set.from_list(["1.5", "2.5", "3.5"])),
        dynamic.float(9.9),
      ),
      False,
    ),
    // String happy path - value in set
    #(
      #(
        refinement_types.OneOf(
          "String",
          set.from_list(["pizza", "pasta", "salad"]),
        ),
        dynamic.string("pizza"),
      ),
      True,
    ),
    // String sad path - value not in set
    #(
      #(
        refinement_types.OneOf(
          "String",
          set.from_list(["pizza", "pasta", "salad"]),
        ),
        dynamic.string("burger"),
      ),
      False,
    ),
    // Wrong type entirely - string when expecting integer
    #(
      #(
        refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"])),
        dynamic.string("not an integer"),
      ),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case refinement_types.validate_value(typ, value, decode_inner) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_to_string ====
// Since we only support Integer, Float, and String initially, this is a fairly small set of tests.
// * ✅ OneOf(Integer) - resolves value to string
// * ✅ OneOf(Float) - resolves value to string
// * ✅ OneOf(String) - resolves value to string
// * ✅ OneOf - decode error returns Error
pub fn resolve_to_string_test() {
  let decode_inner = fn(typ: String) {
    case typ {
      "Integer" -> {
        use val <- decode.then(decode.int)
        decode.success(int.to_string(val))
      }
      "Float" -> {
        use val <- decode.then(decode.float)
        decode.success(float.to_string(val))
      }
      "String" -> decode.string
      _ -> decode.failure("", "Unknown type")
    }
  }
  let resolve_string = fn(x: String) { x }

  [
    // Integer happy path
    #(
      #(
        refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"])),
        dynamic.int(10),
      ),
      Ok("10"),
    ),
    // Float happy path
    #(
      #(
        refinement_types.OneOf("Float", set.from_list(["1.5", "2.5", "3.5"])),
        dynamic.float(1.5),
      ),
      Ok("1.5"),
    ),
    // String happy path
    #(
      #(
        refinement_types.OneOf(
          "String",
          set.from_list(["pasta", "pizza", "salad"]),
        ),
        dynamic.string("pizza"),
      ),
      Ok("pizza"),
    ),
    // Decode error - wrong type
    #(
      #(
        refinement_types.OneOf("Integer", set.from_list(["10", "20", "30"])),
        dynamic.string("not an integer"),
      ),
      Error("Unable to decode refinement type value."),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    refinement_types.resolve_to_string(typ, value, decode_inner, resolve_string)
  })
}
