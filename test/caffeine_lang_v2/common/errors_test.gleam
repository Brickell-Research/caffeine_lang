import caffeine_lang_v2/common/errors
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleeunit/should

// ==== Format JSON Decode Error Tests ====
// * ✅ UnexpectedEndOfInput
// * ✅ UnexpectedByte
// * ✅ UnexpectedSequence
// * ✅ UnableToDecode (single error)
// * ✅ UnableToDecode (multiple errors)
pub fn format_json_decode_error_test() {
  [
    #(json.UnexpectedEndOfInput, "Unexpected end of input."),
    #(json.UnexpectedByte("x"), "Unexpected byte: x."),
    #(json.UnexpectedSequence("abc"), "Unexpected sequence: abc."),
    #(
      json.UnableToDecode([
        decode.DecodeError("String", "Int", ["field", "nested"]),
      ]),
      "Incorrect types: expected (String) received (Int) for (field.nested)",
    ),
    #(
      json.UnableToDecode([
        decode.DecodeError("String", "Int", ["first"]),
        decode.DecodeError("Bool", "Float", ["second"]),
      ]),
      "Incorrect types: expected (String) received (Int) for (first), expected (Bool) received (Float) for (second)",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected_msg) = pair
    errors.format_json_decode_error(input)
    |> should.equal(errors.JsonParserError(expected_msg))
  })
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
  |> list.each(fn(tuple) {
    let #(input_errors, identifier, expected) = tuple
    errors.format_decode_error_message(input_errors, identifier)
    |> should.equal(expected)
  })
}

// ==== Parser Error to Linker Error ====
// * ✅ FileReadError -> LinkerParseError
// * ✅ JsonParserError -> LinkerParseError
// * ✅ DuplicateError -> LinkerParseError
pub fn parser_error_to_linker_error_test() {
  [
    #(
      errors.FileReadError("foo"),
      errors.LinkerParseError("File read error: foo"),
    ),
    #(
      errors.JsonParserError("foo"),
      errors.LinkerParseError("JSON parse error: foo"),
    ),
    #(
      errors.DuplicateError("foo"),
      errors.LinkerParseError("Duplicate error: foo"),
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    errors.parser_error_to_linker_error(input)
    |> should.equal(expected)
  })
}
