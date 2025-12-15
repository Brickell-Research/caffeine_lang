import caffeine_lang/common/decoders
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleeunit/should

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
