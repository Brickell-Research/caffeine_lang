import caffeine_lang/common/helpers
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleeunit/should

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
    #("Defaulted(Boolean, True)", Ok(helpers.Defaulted(helpers.Boolean, "True"))),
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
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    decode.run(dynamic.string(input), helpers.accepted_types_decoder())
    |> should.equal(expected)
  })
}

// ==== Map Reference To Referrer Over Collection Tests ====
// * ✅ happy path - empty collection
// * ✅ happy path - matches references to referrers
pub fn map_reference_to_referrer_over_collection_test() {
  // empty collection
  helpers.map_reference_to_referrer_over_collection(
    references: [],
    referrers: [],
    reference_name: fn(x: #(String, Int)) { x.0 },
    referrer_reference: fn(x: #(String, Int)) { x.0 },
  )
  |> should.equal([])

  // matches references to referrers
  let references = [#("alice", 1), #("bob", 2)]
  let referrers = [#("bob", 100), #("alice", 200)]
  helpers.map_reference_to_referrer_over_collection(
    references:,
    referrers:,
    reference_name: fn(x) { x.0 },
    referrer_reference: fn(x) { x.0 },
  )
  |> should.equal([
    #(#("bob", 100), #("bob", 2)),
    #(#("alice", 200), #("alice", 1)),
  ])
}

// ==== result_try Tests ====
// * ✅ ok value chains to next function
// * ✅ error short-circuits
pub fn result_try_test() {
  // ok value chains to next function
  helpers.result_try(Ok(1), fn(x) { Ok(x + 1) })
  |> should.equal(Ok(2))

  // chained ok values
  helpers.result_try(Ok(5), fn(x) {
    helpers.result_try(Ok(x * 2), fn(y) { Ok(y + 3) })
  })
  |> should.equal(Ok(13))

  // error short-circuits
  helpers.result_try(Error("failed"), fn(_) { Ok(42) })
  |> should.equal(Error("failed"))

  // error in chain short-circuits
  helpers.result_try(Ok(1), fn(_) {
    helpers.result_try(Error("mid-chain error"), fn(y) { Ok(y + 1) })
  })
  |> should.equal(Error("mid-chain error"))
}

// ==== Accepted Type To String Tests ====
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
// * ✅ Optional(Dict(String, String))
// * ✅ Defaulted(String, default)
// * ✅ Defaulted(Integer, 10)
// * ✅ Defaulted(List(String), default)
// * ✅ Defaulted(Dict(String, String), default)
pub fn accepted_type_to_string_test() {
  [
    #(helpers.Boolean, "Boolean"),
    #(helpers.Float, "Float"),
    #(helpers.Integer, "Integer"),
    #(helpers.String, "String"),
    #(helpers.Dict(helpers.String, helpers.String), "Dict(String, String)"),
    #(helpers.Dict(helpers.String, helpers.Integer), "Dict(String, Integer)"),
    #(helpers.Dict(helpers.String, helpers.Float), "Dict(String, Float)"),
    #(helpers.Dict(helpers.String, helpers.Boolean), "Dict(String, Boolean)"),
    #(helpers.List(helpers.String), "List(String)"),
    #(helpers.List(helpers.Integer), "List(Integer)"),
    #(helpers.List(helpers.Float), "List(Float)"),
    #(helpers.List(helpers.Boolean), "List(Boolean)"),
    // Optional basic types
    #(helpers.Optional(helpers.String), "Optional(String)"),
    #(helpers.Optional(helpers.Integer), "Optional(Integer)"),
    #(helpers.Optional(helpers.Float), "Optional(Float)"),
    #(helpers.Optional(helpers.Boolean), "Optional(Boolean)"),
    // Optional nested types
    #(
      helpers.Optional(helpers.List(helpers.String)),
      "Optional(List(String))",
    ),
    #(
      helpers.Optional(helpers.Dict(helpers.String, helpers.String)),
      "Optional(Dict(String, String))",
    ),
    // Defaulted basic types
    #(helpers.Defaulted(helpers.String, "default"), "Defaulted(String, default)"),
    #(helpers.Defaulted(helpers.Integer, "10"), "Defaulted(Integer, 10)"),
    // Defaulted nested types
    #(
      helpers.Defaulted(helpers.List(helpers.String), "default"),
      "Defaulted(List(String), default)",
    ),
    #(
      helpers.Defaulted(helpers.Dict(helpers.String, helpers.String), "default"),
      "Defaulted(Dict(String, String), default)",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    helpers.accepted_type_to_string(input)
    |> should.equal(expected)
  })
}
