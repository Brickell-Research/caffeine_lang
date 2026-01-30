import caffeine_lang/common/errors
import gleam/dynamic
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
    #([], option.None, option.None, ""),
    // single error with path, no identifier, no value
    #(
      [decode.DecodeError("String", "Int", ["field"])],
      option.None,
      option.None,
      "expected (String) received (Int) for (field)",
    ),
    // single error without path, no identifier (shows "Unknown")
    #(
      [decode.DecodeError("String", "Int", [])],
      option.None,
      option.None,
      "expected (String) received (Int) for (Unknown)",
    ),
    // single error without path, with identifier (shows identifier)
    #(
      [decode.DecodeError("String", "Int", [])],
      option.Some("my_field"),
      option.None,
      "expected (String) received (Int) for (my_field)",
    ),
    // single error with path, with identifier (combined: identifier.path)
    #(
      [decode.DecodeError("String", "Int", ["actual", "path"])],
      option.Some("my_identifier"),
      option.None,
      "expected (String) received (Int) for (my_identifier.actual.path)",
    ),
    // multiple errors
    #(
      [
        decode.DecodeError("String", "Int", ["first"]),
        decode.DecodeError("Bool", "Float", ["second"]),
      ],
      option.None,
      option.None,
      "expected (String) received (Int) for (first), expected (Bool) received (Float) for (second)",
    ),
    // single error with value preview (string)
    #(
      [decode.DecodeError("Int", "String", [])],
      option.Some("my_field"),
      option.Some(dynamic.string("hello")),
      "expected (Int) received (String) value (\"hello\") for (my_field)",
    ),
    // single error with value preview (int)
    #(
      [decode.DecodeError("String", "Int", [])],
      option.Some("count"),
      option.Some(dynamic.int(42)),
      "expected (String) received (Int) value (42) for (count)",
    ),
    // single error with value preview (bool)
    #(
      [decode.DecodeError("String", "Bool", [])],
      option.Some("flag"),
      option.Some(dynamic.bool(True)),
      "expected (String) received (Bool) value (True) for (flag)",
    ),
  ]
  |> test_helpers.array_based_test_executor_3(
    errors.format_decode_error_message,
  )
}
