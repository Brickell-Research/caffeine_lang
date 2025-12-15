import caffeine_lang/common/decoders
import caffeine_lang/common/helpers
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import test_helpers

// ==== Named Reference Decoder Tests ====
// * ✅ happy path - name exists in collection
// * ✅ sad path - name doesn't exist in collection
pub fn named_reference_decoder_test() {
  let collection = [#("alice", 1), #("bob", 2)]
  let decoder = decoders.named_reference_decoder(collection, fn(x) { x.0 })

  [
    #("alice", Ok("alice")),
    #("charlie", Error([decode.DecodeError("NamedReference", "String", [])])),
  ]
  |> list.each(fn(pair) {
    decode.run(dynamic.string(pair.0), decoder)
    |> should.equal(pair.1)
  })
}

// ==== Non-Empty String Decoder Tests ====
// ==== Happy Path ====
// * ✅ non-empty string
// * ✅ whitespace-only string (allowed - not empty)
// * ✅ single character
// ==== Sad Path ====
// * ✅ empty string
// * ✅ wrong type (int)
// * ✅ wrong type (bool)
pub fn non_empty_string_decoder_happy_path_test() {
  let decoder = decoders.non_empty_string_decoder()

  [
    #("hello", Ok("hello")),
    #("a", Ok("a")),
    #("   ", Ok("   ")),
    #("hello world", Ok("hello world")),
    #("", Error([decode.DecodeError("NonEmptyString", "String", [])])),
  ]
  |> list.each(fn(pair) {
    decode.run(dynamic.string(pair.0), decoder)
    |> should.equal(pair.1)
  })

  // Wrong type - int
  decode.run(dynamic.int(123), decoder)
  |> should.equal(Error([decode.DecodeError("NonEmptyString", "Int", [])]))

  // Wrong type - bool
  decode.run(dynamic.bool(True), decoder)
  |> should.equal(Error([decode.DecodeError("NonEmptyString", "Bool", [])]))
}

// ==== Accepted Type Tests ====
// Arguably not needed, but anyway should be fine
// * ✅ Boolean
// * ✅ Float
// * ✅ Integer
// * ✅ String
// * ✅ Dict(String, String)
// * ✅ Dict(String, Integer)
// * ✅ Dict(String, Float)
// * ✅ Dict(String, Boolean)
// * ✅ List(String)
// * ✅ List(Integer)
// * ✅ List(Float)
// * ✅ List(Boolean)
// * ✅ Optional(String)
// * ✅ Optional(Integer)
// * ✅ Optional(Float)
// * ✅ Optional(Boolean)
// * ✅ Optional(List(String))
// * ✅ Optional(List(Integer))
// * ✅ Optional(List(Float))
// * ✅ Optional(List(Boolean))
// * ✅ Optional(Dict(String, String))
// * ✅ Optional(Dict(String, Integer))
// * ✅ Optional(Dict(String, Float))
// * ✅ Optional(Dict(String, Boolean))
// * ✅ Defaulted(String, default_value)
// * ✅ Defaulted(Integer, 10)
// * ✅ Defaulted(Float, 3.14)
// * ✅ Defaulted(Boolean, True)
// * ✅ Defaulted(List(String), default)
// * ✅ Defaulted(Dict(String, String), default)
// * ✅ Unrecognized
// * ✅ Invalid Defaulted(Integer, hello) - default doesn't match type
// * ✅ Invalid Defaulted(Float, not_a_float) - default doesn't match type
// * ✅ Invalid Defaulted(Boolean, maybe) - default doesn't match type
pub fn accepted_types_decoder_test() {
  [
    #("Boolean", Ok(helpers.Boolean)),
    #("Float", Ok(helpers.Float)),
    #("Integer", Ok(helpers.Integer)),
    #("String", Ok(helpers.String)),
    #("Dict(String, String)", Ok(helpers.Dict(helpers.String, helpers.String))),
    #(
      "Dict(String, Integer)",
      Ok(helpers.Dict(helpers.String, helpers.Integer)),
    ),
    #("Dict(String, Float)", Ok(helpers.Dict(helpers.String, helpers.Float))),
    #(
      "Dict(String, Boolean)",
      Ok(helpers.Dict(helpers.String, helpers.Boolean)),
    ),
    #("List(String)", Ok(helpers.List(helpers.String))),
    #("List(Integer)", Ok(helpers.List(helpers.Integer))),
    #("List(Float)", Ok(helpers.List(helpers.Float))),
    #("List(Boolean)", Ok(helpers.List(helpers.Boolean))),
    // Optional basic types
    #("Optional(String)", Ok(helpers.Optional(helpers.String))),
    #("Optional(Integer)", Ok(helpers.Optional(helpers.Integer))),
    #("Optional(Float)", Ok(helpers.Optional(helpers.Float))),
    #("Optional(Boolean)", Ok(helpers.Optional(helpers.Boolean))),
    // Optional List types
    #(
      "Optional(List(String))",
      Ok(helpers.Optional(helpers.List(helpers.String))),
    ),
    #(
      "Optional(List(Integer))",
      Ok(helpers.Optional(helpers.List(helpers.Integer))),
    ),
    #(
      "Optional(List(Float))",
      Ok(helpers.Optional(helpers.List(helpers.Float))),
    ),
    #(
      "Optional(List(Boolean))",
      Ok(helpers.Optional(helpers.List(helpers.Boolean))),
    ),
    // Optional Dict types
    #(
      "Optional(Dict(String, String))",
      Ok(helpers.Optional(helpers.Dict(helpers.String, helpers.String))),
    ),
    #(
      "Optional(Dict(String, Integer))",
      Ok(helpers.Optional(helpers.Dict(helpers.String, helpers.Integer))),
    ),
    #(
      "Optional(Dict(String, Float))",
      Ok(helpers.Optional(helpers.Dict(helpers.String, helpers.Float))),
    ),
    #(
      "Optional(Dict(String, Boolean))",
      Ok(helpers.Optional(helpers.Dict(helpers.String, helpers.Boolean))),
    ),
    // Defaulted basic types with default values
    #(
      "Defaulted(String, default_value)",
      Ok(helpers.Defaulted(helpers.String, "default_value")),
    ),
    #("Defaulted(Integer, 10)", Ok(helpers.Defaulted(helpers.Integer, "10"))),
    #("Defaulted(Float, 3.14)", Ok(helpers.Defaulted(helpers.Float, "3.14"))),
    #(
      "Defaulted(Boolean, True)",
      Ok(helpers.Defaulted(helpers.Boolean, "True")),
    ),
    // Defaulted nested types
    #(
      "Defaulted(List(String), default)",
      Ok(helpers.Defaulted(helpers.List(helpers.String), "default")),
    ),
    #(
      "Defaulted(Dict(String, String), default)",
      Ok(helpers.Defaulted(
        helpers.Dict(helpers.String, helpers.String),
        "default",
      )),
    ),
    #("UnknownType", Error([decode.DecodeError("AcceptedType", "String", [])])),
    // Invalid Defaulted types - default value doesn't match inner type
    #(
      "Defaulted(Integer, hello)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Defaulted(Float, not_a_float)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Defaulted(Boolean, maybe)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(dynamic.string(input), decoders.accepted_types_decoder())
  })
}
