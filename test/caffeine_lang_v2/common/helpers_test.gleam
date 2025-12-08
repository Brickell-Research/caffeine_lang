import caffeine_lang_v2/common/helpers
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
// * ✅ Unrecognized
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
    #("UnknownType", Error([decode.DecodeError("AcceptedType", "String", [])])),
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
