import caffeine_lang/common/helpers
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

// ==== result_try ====
// * ✅ ok value chains to next function
// * ✅ chained ok values
// * ✅ error short-circuits
// * ✅ error in chain short-circuits
pub fn result_try_test() {
  [
    // ok value chains to next function
    #(#(Ok(1), fn(x) { Ok(x + 1) }), Ok(2)),
    // error short-circuits
    #(#(Error("failed"), fn(_) { Ok(42) }), Error("failed")),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(initial, mapper) = input
    helpers.result_try(initial, mapper)
  })

  // chained ok values - more complex test
  [
    #(5, Ok(13)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(x) {
    helpers.result_try(Ok(x), fn(y) {
      helpers.result_try(Ok(y * 2), fn(z) { Ok(z + 3) })
    })
  })

  // error in chain short-circuits
  [
    #(1, Error("mid-chain error")),
  ]
  |> test_helpers.array_based_test_executor_1(fn(x) {
    helpers.result_try(Ok(x), fn(_) {
      helpers.result_try(Error("mid-chain error"), fn(y) { Ok(y + 1) })
    })
  })
}
