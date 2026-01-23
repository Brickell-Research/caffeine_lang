import caffeine_lang/common/accepted_types
import caffeine_lang/common/helpers
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import gleam/dynamic
import gleam/dynamic/decode
import gleeunit/should
import test_helpers

// ==== map_reference_to_referrer_over_collection ====
// * ✅ happy path - empty collection
// * ✅ happy path - matches references to referrers
pub fn map_reference_to_referrer_over_collection_test() {
  [
    // empty collection
    #(#([], []), []),
    // matches references to referrers
    #(#([#("alice", 1), #("bob", 2)], [#("bob", 100), #("alice", 200)]), [
      #(#("bob", 100), #("bob", 2)),
      #(#("alice", 200), #("alice", 1)),
    ]),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(references, referrers) = input
    helpers.map_reference_to_referrer_over_collection(
      references:,
      referrers:,
      reference_name: fn(x: #(String, Int)) { x.0 },
      referrer_reference: fn(x: #(String, Int)) { x.0 },
    )
  })
}

// ==== extract_value ====
// * ✅ extracts value by label
// * ✅ returns Error for missing label
// * ✅ returns Error for decode failure
pub fn extract_value_test() {
  let values = [
    helpers.ValueTuple(
      "name",
      accepted_types.PrimitiveType(primitive_types.String),
      dynamic.string("hello"),
    ),
    helpers.ValueTuple(
      "count",
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Integer,
      )),
      dynamic.int(42),
    ),
  ]

  // extracts value by label
  helpers.extract_value(values, "name", decode.string)
  |> should.equal(Ok("hello"))

  // extracts value with different decoder
  helpers.extract_value(values, "count", decode.int)
  |> should.equal(Ok(42))

  // returns Error for missing label
  helpers.extract_value(values, "missing", decode.string)
  |> should.equal(Error(Nil))

  // returns Error for decode failure (wrong decoder for type)
  helpers.extract_value(values, "count", decode.string)
  |> should.equal(Error(Nil))
}
