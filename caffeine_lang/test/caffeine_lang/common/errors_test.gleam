import caffeine_lang/common/errors
import gleam/dynamic/decode
import gleam/json
import gleam/option
import test_helpers

// ==== Format JSON Decode Error Tests ====
// * ✅ UnexpectedEndOfInput
// * ✅ UnexpectedByte
// * ✅ UnexpectedSequence
// * ✅ UnableToDecode (single error)
// * ✅ UnableToDecode (multiple errors)
pub fn format_json_decode_error_test() {
  [
    #(
      json.UnexpectedEndOfInput,
      errors.ParserJsonParserError("Unexpected end of input."),
    ),
    #(
      json.UnexpectedByte("x"),
      errors.ParserJsonParserError("Unexpected byte: x."),
    ),
    #(
      json.UnexpectedSequence("abc"),
      errors.ParserJsonParserError("Unexpected sequence: abc."),
    ),
    #(
      json.UnableToDecode([
        decode.DecodeError("String", "Int", ["field", "nested"]),
      ]),
      errors.ParserJsonParserError(
        "Incorrect types: expected (String) received (Int) for (field.nested)",
      ),
    ),
    #(
      json.UnableToDecode([
        decode.DecodeError("String", "Int", ["first"]),
        decode.DecodeError("Bool", "Float", ["second"]),
      ]),
      errors.ParserJsonParserError(
        "Incorrect types: expected (String) received (Int) for (first), expected (Bool) received (Float) for (second)",
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(errors.format_json_decode_error)
}

// ==== Format Decode Error Message Tests ====
// * ✅ empty list
// * ✅ single error with path, no identifier
// * ✅ single error without path, no identifier (shows "Unknown")
// * ✅ single error without path, with identifier (shows identifier)
// * ✅ single error with path, with identifier (path takes precedence)
// * ✅ multiple errors
pub fn format_decode_error_message_test() {
  [
    // empty list
    #([], option.None, ""),
    // single error with path, no identifier
    #(
      [decode.DecodeError("String", "Int", ["field"])],
      option.None,
      "expected (String) received (Int) for (field)",
    ),
    // single error without path, no identifier (shows "Unknown")
    #(
      [decode.DecodeError("String", "Int", [])],
      option.None,
      "expected (String) received (Int) for (Unknown)",
    ),
    // single error without path, with identifier (shows identifier)
    #(
      [decode.DecodeError("String", "Int", [])],
      option.Some("my_field"),
      "expected (String) received (Int) for (my_field)",
    ),
    // single error with path, with identifier (path takes precedence)
    #(
      [decode.DecodeError("String", "Int", ["actual", "path"])],
      option.Some("ignored_identifier"),
      "expected (String) received (Int) for (actual.path)",
    ),
    // multiple errors
    #(
      [
        decode.DecodeError("String", "Int", ["first"]),
        decode.DecodeError("Bool", "Float", ["second"]),
      ],
      option.None,
      "expected (String) received (Int) for (first), expected (Bool) received (Float) for (second)",
    ),
  ]
  |> test_helpers.array_based_test_executor_2(
    errors.format_decode_error_message,
  )
}
