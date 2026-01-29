import caffeine_lang/common/semantic_types
import gleam/dynamic
import gleam/dynamic/decode
import test_helpers

// ==== parse_semantic_type ====
// ==== Happy Path ====
// * ✅ URL
// ==== Sad Path ====
// * ✅ lowercase url
// * ✅ Empty string
pub fn parse_semantic_type_test() {
  [
    #("URL", Ok(semantic_types.URL)),
    #("url", Error(Nil)),
    #("", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(semantic_types.parse_semantic_type)
}

// ==== semantic_type_to_string ====
// * ✅ URL -> "URL"
pub fn semantic_type_to_string_test() {
  [#(semantic_types.URL, "URL")]
  |> test_helpers.array_based_test_executor_1(
    semantic_types.semantic_type_to_string,
  )
}

// ==== decode_semantic_to_string ====
// * ✅ String dynamic -> Ok(string)
pub fn decode_semantic_to_string_test() {
  [
    #(dynamic.string("https://example.com"), Ok("https://example.com")),
    #(dynamic.string("http://example.com"), Ok("http://example.com")),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    decode.run(
      input,
      semantic_types.decode_semantic_to_string(semantic_types.URL),
    )
  })
}

// ==== validate_default_value ====
// ==== Happy Path ====
// * ✅ Valid https URL
// * ✅ Valid http URL
// ==== Sad Path ====
// * ✅ Non-URL string
// * ✅ Empty string
pub fn validate_default_value_test() {
  [
    #(#(semantic_types.URL, "https://example.com"), Ok(Nil)),
    #(#(semantic_types.URL, "http://example.com"), Ok(Nil)),
    #(
      #(semantic_types.URL, "https://wiki.example.com/runbook/auth-latency"),
      Ok(Nil),
    ),
    #(#(semantic_types.URL, "not-a-url"), Error(Nil)),
    #(#(semantic_types.URL, ""), Error(Nil)),
    #(#(semantic_types.URL, "ftp://example.com"), Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    semantic_types.validate_default_value(input.0, input.1)
  })
}

// ==== validate_value ====
// ==== Happy Path ====
// * ✅ String dynamic with valid URL
// ==== Sad Path ====
// * ✅ String dynamic with invalid URL
// * ✅ Non-string dynamic
pub fn validate_value_test() {
  let valid_url = dynamic.string("https://example.com")
  let invalid_url = dynamic.string("not-a-url")
  let int_val = dynamic.int(42)

  // Valid URL
  [#(#(semantic_types.URL, valid_url), Ok(valid_url))]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    semantic_types.validate_value(input.0, input.1)
  })

  // Invalid URL string
  [
    #(
      #(semantic_types.URL, invalid_url),
      Error([
        decode.DecodeError(
          expected: "URL (starting with http:// or https://)",
          found: "String",
          path: [],
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    semantic_types.validate_value(input.0, input.1)
  })

  // Non-string value
  [
    #(
      #(semantic_types.URL, int_val),
      Error([
        decode.DecodeError(expected: "String", found: "Int", path: []),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    semantic_types.validate_value(input.0, input.1)
  })
}
