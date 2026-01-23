import caffeine_lang/standard_library/artifacts
import gleam/dynamic/decode
import gleam/json
import test_helpers

// ==== standard_library ====
// * ✅ ensure this is parsable json
pub fn standard_library_test() {
  [
    #(artifacts.standard_library, True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    case json.parse(from: input, using: decode.dynamic) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}
