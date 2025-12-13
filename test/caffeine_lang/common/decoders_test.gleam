import caffeine_lang/common/decoders
import gleam/dynamic
import gleam/dynamic/decode
import test_helpers

// ==== Named Reference Decoder Tests ====
// * ✅ happy path - name exists in collection
// * ✅ sad path - name doesn't exist in collection
pub fn named_reference_decoder_test() {
  let collection = [#("alice", 1), #("bob", 2)]
  let decoder = decoders.named_reference_decoder(collection, fn(x) { x.0 })

  test_helpers.array_based_test_executor_1(
    [
      #("alice", Ok("alice")),
      #("charlie", Error([decode.DecodeError("NamedReference", "String", [])])),
    ],
    fn(input) { decode.run(dynamic.string(input), decoder) },
  )
}
