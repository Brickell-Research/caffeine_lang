import caffeine_lang_v2/common/decoders
import gleam/dynamic
import gleam/dynamic/decode
import gleeunit/should

// ==== Named Reference Decoder Tests ====
// * ✅ happy path - name exists in collection
// * ✅ sad path - name doesn't exist in collection
pub fn named_reference_decoder_test() {
  let collection = [#("alice", 1), #("bob", 2)]
  let decoder = decoders.named_reference_decoder(collection, fn(x) { x.0 })

  // happy path
  decode.run(dynamic.string("alice"), decoder) |> should.be_ok

  // sad path
  decode.run(dynamic.string("charlie"), decoder) |> should.be_error
}
