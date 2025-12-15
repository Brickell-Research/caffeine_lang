import caffeine_lang/standard_library/artifacts
import gleam/dynamic/decode
import gleam/json
import gleeunit/should

// ==== Standard Library ====
// * ✅ ensure this is parsable json
pub fn standard_library_is_valid_json_test() {
  json.parse(from: artifacts.standard_library, using: decode.dynamic)
  |> should.be_ok()
}
