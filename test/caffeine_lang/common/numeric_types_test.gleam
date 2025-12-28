import caffeine_lang/common/numeric_types
import gleam/dynamic
import gleam/dynamic/decode
import test_helpers

// ==== parse_numeric_type ====
// ==== Happy Path ====
// * ✅ Float
// * ✅ Integer
// ==== Sad Path ====
// * ✅ Unknown type
// * ✅ Empty string
pub fn parse_numeric_type_test() {
  [
    #("Float", Ok(numeric_types.Float)),
    #("Integer", Ok(numeric_types.Integer)),
    #("Unknown", Error(Nil)),
    #("", Error(Nil)),
    #("float", Error(Nil)),
    #("integer", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(numeric_types.parse_numeric_type)
}

// ==== numeric_type_to_string ====
// * ✅ Float -> "Float"
// * ✅ Integer -> "Integer"
pub fn numeric_type_to_string_test() {
  [
    #(numeric_types.Float, "Float"),
    #(numeric_types.Integer, "Integer"),
  ]
  |> test_helpers.array_based_test_executor_1(
    numeric_types.numeric_type_to_string,
  )
}

// ==== decode_numeric_to_string ====
// * ✅ Float -> string representation
// * ✅ Integer -> string representation
pub fn decode_numeric_to_string_test() {
  // Integer decoder
  [
    #(dynamic.int(42), Ok("42")),
    #(dynamic.int(-10), Ok("-10")),
    #(dynamic.int(0), Ok("0")),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      numeric_types.decode_numeric_to_string(numeric_types.Integer),
    )
  })

  // Float decoder
  [
    #(dynamic.float(3.14), Ok("3.14")),
    #(dynamic.float(-1.5), Ok("-1.5")),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      numeric_types.decode_numeric_to_string(numeric_types.Float),
    )
  })
}

// ==== validate_default_value ====
// ==== Happy Path ====
// * ✅ Integer with valid int string
// * ✅ Float with valid float string
// ==== Sad Path ====
// * ✅ Integer with non-integer string
// * ✅ Float with non-float string
pub fn validate_default_value_test() {
  [
    // Integer
    #(#(numeric_types.Integer, "42"), Ok(Nil)),
    #(#(numeric_types.Integer, "-10"), Ok(Nil)),
    #(#(numeric_types.Integer, "0"), Ok(Nil)),
    #(#(numeric_types.Integer, "hello"), Error(Nil)),
    #(#(numeric_types.Integer, "3.14"), Error(Nil)),
    // Float
    #(#(numeric_types.Float, "3.14"), Ok(Nil)),
    #(#(numeric_types.Float, "-1.5"), Ok(Nil)),
    #(#(numeric_types.Float, "hello"), Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_default_value(input.0, input.1)
  })
}
