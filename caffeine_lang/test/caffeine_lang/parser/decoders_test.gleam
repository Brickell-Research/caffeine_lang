import caffeine_lang/common/accepted_types
import caffeine_lang/parser/decoders
import caffeine_lang/common/primitive_types
import gleam/dynamic
import gleam/dynamic/decode
import test_helpers

// ==== named_reference_decoder ====
// ==== Happy Path ====
// * ✅ name exists in collection
// ==== Sad Path ====
// * ✅ name doesn't exist in collection
pub fn named_reference_decoder_test() {
  let collection = [#("alice", 1), #("bob", 2)]
  let decoder = decoders.named_reference_decoder(from: collection, by: fn(x) { x.0 })

  [
    #(dynamic.string("alice"), Ok("alice")),
    #(
      dynamic.string("charlie"),
      Error([
        decode.DecodeError(
          "NamedReference (one of: alice, bob)",
          "String",
          [],
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(input, decoder)
  })
}

// ==== non_empty_string_decoder ====
// ==== Happy Path ====
// * ✅ non-empty string
// * ✅ whitespace-only string (allowed - not empty)
// * ✅ single character
// ==== Sad Path ====
// * ✅ empty string
// * ✅ wrong type (int)
// * ✅ wrong type (bool)
pub fn non_empty_string_decoder_test() {
  let decoder = decoders.non_empty_string_decoder()

  [
    #(dynamic.string("hello"), Ok("hello")),
    #(dynamic.string("a"), Ok("a")),
    #(dynamic.string("   "), Ok("   ")),
    #(dynamic.string("hello world"), Ok("hello world")),
    #(
      dynamic.string(""),
      Error([
        decode.DecodeError("NonEmptyString (got empty string)", "String", []),
      ]),
    ),
    #(
      dynamic.int(123),
      Error([decode.DecodeError("String", "Int", [])]),
    ),
    #(
      dynamic.bool(True),
      Error([decode.DecodeError("String", "Bool", [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(input, decoder)
  })
}

// ==== accepted_types_decoder ====
// Tests the decoder wrapper around parse_accepted_type.
// Full parsing logic is tested in accepted_types_test.gleam.
// This test focuses on decoder-specific behavior (error format).
// ==== Happy Path ====
// * ✅ Valid type parses
// ==== Sad Path ====
// * ✅ Invalid type returns decoder error format
pub fn accepted_types_decoder_test() {
  [
    #("String", Ok(accepted_types.PrimitiveType(primitive_types.String))),
    #(
      "UnknownType",
      Error([
        decode.DecodeError("AcceptedType (unknown: UnknownType)", "String", []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(dynamic.string(input), decoders.accepted_types_decoder())
  })
}
