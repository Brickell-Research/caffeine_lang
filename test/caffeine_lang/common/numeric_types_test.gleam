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

// ==== validate_value ====
// ==== Happy Path ====
// * ✅ Integer with valid int dynamic
// * ✅ Float with valid float dynamic
// ==== Sad Path ====
// * ✅ Integer with non-integer dynamic
// * ✅ Float with non-float dynamic
pub fn validate_value_test() {
  let int_val = dynamic.int(42)
  let float_val = dynamic.float(3.14)
  let string_val = dynamic.string("hello")

  // Integer validation
  [
    #(#(numeric_types.Integer, int_val), Ok(int_val)),
    #(
      #(numeric_types.Integer, string_val),
      Error([decode.DecodeError(expected: "Int", found: "String", path: [])]),
    ),
    #(
      #(numeric_types.Integer, float_val),
      Error([decode.DecodeError(expected: "Int", found: "Float", path: [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_value(input.0, input.1)
  })

  // Float validation
  [
    #(#(numeric_types.Float, float_val), Ok(float_val)),
    #(
      #(numeric_types.Float, string_val),
      Error([decode.DecodeError(expected: "Float", found: "String", path: [])]),
    ),
    #(
      #(numeric_types.Float, int_val),
      Error([decode.DecodeError(expected: "Float", found: "Int", path: [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_value(input.0, input.1)
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
    #(#(numeric_types.Integer, "50", "0", "100"), Ok(Nil)),
    #(#(numeric_types.Integer, "0", "0", "100"), Ok(Nil)),
    #(#(numeric_types.Integer, "100", "0", "100"), Ok(Nil)),
    #(#(numeric_types.Integer, "-5", "-10", "10"), Ok(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Integer - sad path (out of range)
  [
    #(
      #(numeric_types.Integer, "-1", "0", "100"),
      Error([
        decode.DecodeError(expected: "0 <= x <= 100", found: "-1", path: []),
      ]),
    ),
    #(
      #(numeric_types.Integer, "-20", "-10", "10"),
      Error([
        decode.DecodeError(expected: "-10 <= x <= 10", found: "-20", path: []),
      ]),
    ),
    #(
      #(numeric_types.Integer, "101", "0", "100"),
      Error([
        decode.DecodeError(expected: "0 <= x <= 100", found: "101", path: []),
      ]),
    ),
    #(
      #(numeric_types.Integer, "15", "-10", "10"),
      Error([
        decode.DecodeError(expected: "-10 <= x <= 10", found: "15", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Integer - sad path (invalid value)
  [
    #(
      #(numeric_types.Integer, "hello", "0", "100"),
      Error([decode.DecodeError(expected: "Integer", found: "hello", path: [])]),
    ),
    #(
      #(numeric_types.Integer, "3.14", "0", "100"),
      Error([decode.DecodeError(expected: "Integer", found: "3.14", path: [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - happy path
  [
    #(#(numeric_types.Float, "0.5", "0.0", "1.0"), Ok(Nil)),
    #(#(numeric_types.Float, "0.0", "0.0", "1.0"), Ok(Nil)),
    #(#(numeric_types.Float, "1.0", "0.0", "1.0"), Ok(Nil)),
    #(#(numeric_types.Float, "-0.5", "-1.0", "1.0"), Ok(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - sad path (out of range)
  [
    #(
      #(numeric_types.Float, "-0.1", "0.0", "1.0"),
      Error([
        decode.DecodeError(expected: "0.0 <= x <= 1.0", found: "-0.1", path: []),
      ]),
    ),
    #(
      #(numeric_types.Float, "1.1", "0.0", "1.0"),
      Error([
        decode.DecodeError(expected: "0.0 <= x <= 1.0", found: "1.1", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_in_range(input.0, input.1, input.2, input.3)
  })

  // Float - sad path (invalid value)
  [
    #(
      #(numeric_types.Float, "hello", "0.0", "1.0"),
      Error([decode.DecodeError(expected: "Float", found: "hello", path: [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    numeric_types.validate_in_range(input.0, input.1, input.2, input.3)
  })
}
