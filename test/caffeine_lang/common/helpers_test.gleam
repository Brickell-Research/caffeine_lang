import caffeine_lang/common/helpers
import gleeunit/should
import test_helpers

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
    #(helpers.Optional(helpers.List(helpers.String)), "Optional(List(String))"),
    #(
      helpers.Optional(helpers.Dict(helpers.String, helpers.String)),
      "Optional(Dict(String, String))",
    ),
    // Defaulted basic types
    #(
      helpers.Defaulted(helpers.String, "default"),
      "Defaulted(String, default)",
    ),
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
  |> test_helpers.array_based_test_executor_1(helpers.accepted_type_to_string)
}
