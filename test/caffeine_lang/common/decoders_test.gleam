import caffeine_lang/common/accepted_types.{
  Boolean, CollectionType, Defaulted, Dict, Float, Integer, List, ModifierType,
  Optional, PrimitiveType, String,
}
import caffeine_lang/common/decoders
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import test_helpers

// ==== Named Reference Decoder Tests ====
// ==== Happy Path ====
// * ✅ name exists in collection
// ==== Sad Path ====
// * ✅ name doesn't exist in collection
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

// ==== Accepted Types Decoder Tests ====
// ==== Primitives ====
// * ✅ Boolean
// * ✅ Float
// * ✅ Integer
// * ✅ String
// ==== Collections - Dict ====
// * ✅ Dict(String, String)
// * ✅ Dict(String, Integer)
// * ✅ Dict(String, Float)
// * ✅ Dict(String, Boolean)
// * ✅ Dict(Integer, String)
// * ✅ Dict(Float, String)
// * ✅ Dict(Boolean, String)
// ==== Collections - List ====
// * ✅ List(String)
// * ✅ List(Integer)
// * ✅ List(Float)
// * ✅ List(Boolean)
// ==== Modifier Types - Optional ====
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
// ==== Modifier Types - Defaulted ====
// * ✅ Defaulted(String, default_value)
// * ✅ Defaulted(Integer, 10)
// * ✅ Defaulted(Float, 3.14)
// * ✅ Defaulted(Boolean, True)
// * ✅ Defaulted(Boolean, False)
// ==== Invalid - Unrecognized ====
// * ✅ UnknownType
// * ✅ Empty string
// * ✅ Whitespace only
// ==== Invalid - Defaulted with mismatched default value ====
// * ✅ Defaulted(Integer, hello)
// * ✅ Defaulted(Float, not_a_float)
// * ✅ Defaulted(Boolean, maybe)
// ==== Invalid - Nested collections not allowed ====
// * ✅ List(List(String)) - cannot have Lists in Lists
// * ✅ List(Dict(String, String)) - cannot have Dicts in Lists
// * ✅ Dict(String, List(String)) - cannot have List as Dict value
// * ✅ Dict(String, Dict(String, String)) - cannot have Dict as Dict value
// * ✅ Dict(List(String), String) - cannot have List as Dict key
// * ✅ Dict(Dict(String, String), String) - cannot have Dict as Dict key
// ==== Invalid - Nested modifiers not allowed ====
// * ✅ Optional(Optional(String)) - cannot have Optional within Optional
// * ✅ Optional(Defaulted(String, default)) - cannot have Defaulted within Optional
// * ✅ Defaulted(Optional(String), default) - cannot have Optional within Defaulted
// * ✅ Defaulted(Defaulted(String, inner), outer) - cannot have Defaulted within Defaulted
// ==== Invalid - Defaulted only allows primitives ====
// * ✅ Defaulted(List(String), default) - cannot have List in Defaulted
// * ✅ Defaulted(Dict(String, String), default) - cannot have Dict in Defaulted
pub fn accepted_types_decoder_test() {
  [
    // ==== Primitives ====
    #("Boolean", Ok(PrimitiveType(Boolean))),
    #("Float", Ok(PrimitiveType(Float))),
    #("Integer", Ok(PrimitiveType(Integer))),
    #("String", Ok(PrimitiveType(String))),
    // ==== Collections - Dict ====
    #(
      "Dict(String, String)",
      Ok(CollectionType(Dict(PrimitiveType(String), PrimitiveType(String)))),
    ),
    #(
      "Dict(String, Integer)",
      Ok(CollectionType(Dict(PrimitiveType(String), PrimitiveType(Integer)))),
    ),
    #(
      "Dict(String, Float)",
      Ok(CollectionType(Dict(PrimitiveType(String), PrimitiveType(Float)))),
    ),
    #(
      "Dict(String, Boolean)",
      Ok(CollectionType(Dict(PrimitiveType(String), PrimitiveType(Boolean)))),
    ),
    #(
      "Dict(Integer, String)",
      Ok(CollectionType(Dict(PrimitiveType(Integer), PrimitiveType(String)))),
    ),
    #(
      "Dict(Float, String)",
      Ok(CollectionType(Dict(PrimitiveType(Float), PrimitiveType(String)))),
    ),
    #(
      "Dict(Boolean, String)",
      Ok(CollectionType(Dict(PrimitiveType(Boolean), PrimitiveType(String)))),
    ),
    // ==== Collections - List ====
    #("List(String)", Ok(CollectionType(List(PrimitiveType(String))))),
    #("List(Integer)", Ok(CollectionType(List(PrimitiveType(Integer))))),
    #("List(Float)", Ok(CollectionType(List(PrimitiveType(Float))))),
    #("List(Boolean)", Ok(CollectionType(List(PrimitiveType(Boolean))))),
    // ==== Modifier Types - Optional basic types ====
    #("Optional(String)", Ok(ModifierType(Optional(PrimitiveType(String))))),
    #("Optional(Integer)", Ok(ModifierType(Optional(PrimitiveType(Integer))))),
    #("Optional(Float)", Ok(ModifierType(Optional(PrimitiveType(Float))))),
    #("Optional(Boolean)", Ok(ModifierType(Optional(PrimitiveType(Boolean))))),
    // ==== Modifier Types - Optional List types ====
    #(
      "Optional(List(String))",
      Ok(ModifierType(Optional(CollectionType(List(PrimitiveType(String)))))),
    ),
    #(
      "Optional(List(Integer))",
      Ok(ModifierType(Optional(CollectionType(List(PrimitiveType(Integer)))))),
    ),
    #(
      "Optional(List(Float))",
      Ok(ModifierType(Optional(CollectionType(List(PrimitiveType(Float)))))),
    ),
    #(
      "Optional(List(Boolean))",
      Ok(ModifierType(Optional(CollectionType(List(PrimitiveType(Boolean)))))),
    ),
    // ==== Modifier Types - Optional Dict types ====
    #(
      "Optional(Dict(String, String))",
      Ok(
        ModifierType(
          Optional(
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
          ),
        ),
      ),
    ),
    #(
      "Optional(Dict(String, Integer))",
      Ok(
        ModifierType(
          Optional(
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(Integer))),
          ),
        ),
      ),
    ),
    #(
      "Optional(Dict(String, Float))",
      Ok(
        ModifierType(
          Optional(
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(Float))),
          ),
        ),
      ),
    ),
    #(
      "Optional(Dict(String, Boolean))",
      Ok(
        ModifierType(
          Optional(
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(Boolean))),
          ),
        ),
      ),
    ),
    // ==== Modifier Types - Defaulted basic types ====
    #(
      "Defaulted(String, default_value)",
      Ok(ModifierType(Defaulted(PrimitiveType(String), "default_value"))),
    ),
    #(
      "Defaulted(Integer, 10)",
      Ok(ModifierType(Defaulted(PrimitiveType(Integer), "10"))),
    ),
    #(
      "Defaulted(Float, 3.14)",
      Ok(ModifierType(Defaulted(PrimitiveType(Float), "3.14"))),
    ),
    #(
      "Defaulted(Boolean, True)",
      Ok(ModifierType(Defaulted(PrimitiveType(Boolean), "True"))),
    ),
    #(
      "Defaulted(Boolean, False)",
      Ok(ModifierType(Defaulted(PrimitiveType(Boolean), "False"))),
    ),
    // ==== Invalid - Unrecognized ====
    #("UnknownType", Error([decode.DecodeError("AcceptedType", "String", [])])),
    #("", Error([decode.DecodeError("AcceptedType", "String", [])])),
    #("   ", Error([decode.DecodeError("AcceptedType", "String", [])])),
    // ==== Invalid - Defaulted with mismatched default value ====
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
    // ==== Invalid - Nested collections not allowed ====
    #(
      "List(List(String))",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "List(Dict(String, String))",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Dict(String, List(String))",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Dict(String, Dict(String, String))",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Dict(List(String), String)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Dict(Dict(String, String), String)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    // ==== Invalid - Nested modifiers not allowed ====
    #(
      "Optional(Optional(String))",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Optional(Defaulted(String, default))",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Defaulted(Optional(String), default)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Defaulted(Defaulted(String, inner), outer)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    // ==== Invalid - Defaulted only allows primitives ====
    #(
      "Defaulted(List(String), default)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
    #(
      "Defaulted(Dict(String, String), default)",
      Error([decode.DecodeError("AcceptedType", "String", [])]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(dynamic.string(input), decoders.accepted_types_decoder())
  })
}
