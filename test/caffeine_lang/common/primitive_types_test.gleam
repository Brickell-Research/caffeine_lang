import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import gleam/dynamic
import gleam/dynamic/decode
import test_helpers

// ==== parse_primitive_type ====
// * ✅ Boolean
// * ✅ String
// * ✅ delegates to numeric_types for Float/Integer
// * ✅ Unknown type returns Error
pub fn parse_primitive_type_test() {
  [
    #("Boolean", Ok(primitive_types.Boolean)),
    #("String", Ok(primitive_types.String)),
    // Integration: delegates to numeric_types
    #("Float", Ok(primitive_types.NumericType(numeric_types.Float))),
    #("Integer", Ok(primitive_types.NumericType(numeric_types.Integer))),
    // Sad path
    #("Unknown", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(primitive_types.parse_primitive_type)
}

// ==== primitive_type_to_string ====
// * ✅ Boolean -> "Boolean"
// * ✅ String -> "String"
// * ✅ delegates to numeric_types for NumericType
pub fn primitive_type_to_string_test() {
  [
    #(primitive_types.Boolean, "Boolean"),
    #(primitive_types.String, "String"),
    // Integration: delegates to numeric_types
    #(primitive_types.NumericType(numeric_types.Float), "Float"),
  ]
  |> test_helpers.array_based_test_executor_1(
    primitive_types.primitive_type_to_string,
  )
}

// ==== decode_primitive_to_string ====
// * ✅ Boolean -> "True"/"False"
// * ✅ String -> same string
// * ✅ delegates to numeric_types for NumericType
pub fn decode_primitive_to_string_test() {
  // Boolean
  [#(dynamic.bool(True), Ok("True"))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      primitive_types.decode_primitive_to_string(primitive_types.Boolean),
    )
  })

  // String
  [#(dynamic.string("hello"), Ok("hello"))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      primitive_types.decode_primitive_to_string(primitive_types.String),
    )
  })

  // Integration: delegates to numeric_types
  [#(dynamic.int(42), Ok("42"))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      primitive_types.decode_primitive_to_string(
        primitive_types.NumericType(numeric_types.Integer),
      ),
    )
  })
}

// ==== validate_default_value ====
// * ✅ Boolean with True/False
// * ✅ Boolean with invalid value
// * ✅ String accepts any value
// * ✅ delegates to numeric_types for NumericType
pub fn validate_default_value_test() {
  [
    // Boolean
    #(#(primitive_types.Boolean, "True"), Ok(Nil)),
    #(#(primitive_types.Boolean, "False"), Ok(Nil)),
    #(#(primitive_types.Boolean, "invalid"), Error(Nil)),
    // String
    #(#(primitive_types.String, "anything"), Ok(Nil)),
    // Integration: delegates to numeric_types
    #(#(primitive_types.NumericType(numeric_types.Integer), "42"), Ok(Nil)),
    #(#(primitive_types.NumericType(numeric_types.Integer), "bad"), Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    primitive_types.validate_default_value(input.0, input.1)
  })
}

// ==== validate_value ====
// * ✅ Boolean validates bool
// * ✅ String validates string
// * ✅ delegates to numeric_types for NumericType
pub fn validate_value_test() {
  [
    #(#(primitive_types.Boolean, dynamic.bool(True)), True),
    #(#(primitive_types.Boolean, dynamic.string("not bool")), False),
    #(#(primitive_types.String, dynamic.string("hello")), True),
    #(#(primitive_types.String, dynamic.int(42)), False),
    // Integration: delegates to numeric_types
    #(#(primitive_types.NumericType(numeric_types.Integer), dynamic.int(42)), True),
    #(#(primitive_types.NumericType(numeric_types.Float), dynamic.float(3.14)), True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    case primitive_types.validate_value(typ, value) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

// ==== resolve_to_string ====
// * ✅ Boolean resolves with resolver
// * ✅ String resolves with resolver
// * ✅ delegates to numeric_types for NumericType
pub fn resolve_to_string_test() {
  let resolver = fn(s) { "resolved:" <> s }

  [
    #(#(primitive_types.Boolean, dynamic.bool(True)), "resolved:True"),
    #(#(primitive_types.String, dynamic.string("hello")), "resolved:hello"),
    // Integration: delegates to numeric_types
    #(
      #(primitive_types.NumericType(numeric_types.Integer), dynamic.int(42)),
      "resolved:42",
    ),
    #(
      #(primitive_types.NumericType(numeric_types.Float), dynamic.float(3.14)),
      "resolved:3.14",
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(typ, value) = input
    primitive_types.resolve_to_string(typ, value, resolver)
  })
}
