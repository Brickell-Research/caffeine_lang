import caffeine_lang/errors
import gleam/dynamic
import gleam/dynamic/decode
import gleam/option
import test_helpers

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
