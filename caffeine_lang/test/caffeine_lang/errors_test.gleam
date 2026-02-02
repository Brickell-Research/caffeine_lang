import caffeine_lang/errors
import caffeine_lang/types
import caffeine_lang/value
import gleam/option
import test_helpers

// ==== Format Decode Error Message Tests ====
// * ✅ empty list
// * ✅ single error with path, no identifier
// * ✅ single error without path, no identifier (shows "Unknown")
// * ✅ single error without path, with identifier (shows identifier)
// * ✅ single error with path, with identifier (path takes precedence)
// * ✅ multiple errors
pub fn format_validation_error_message_test() {
  [
    // empty list
    #([], option.None, option.None, ""),
    // single error with path, no identifier, no value
    #(
      [types.ValidationError("String", "Int", ["field"])],
      option.None,
      option.None,
      "expected (String) received (Int) for (field)",
    ),
    // single error without path, no identifier (shows "Unknown")
    #(
      [types.ValidationError("String", "Int", [])],
      option.None,
      option.None,
      "expected (String) received (Int) for (Unknown)",
    ),
    // single error without path, with identifier (shows identifier)
    #(
      [types.ValidationError("String", "Int", [])],
      option.Some("my_field"),
      option.None,
      "expected (String) received (Int) for (my_field)",
    ),
    // single error with path, with identifier (combined: identifier.path)
    #(
      [types.ValidationError("String", "Int", ["actual", "path"])],
      option.Some("my_identifier"),
      option.None,
      "expected (String) received (Int) for (my_identifier.actual.path)",
    ),
    // multiple errors
    #(
      [
        types.ValidationError("String", "Int", ["first"]),
        types.ValidationError("Bool", "Float", ["second"]),
      ],
      option.None,
      option.None,
      "expected (String) received (Int) for (first), expected (Bool) received (Float) for (second)",
    ),
    // single error with value preview (string)
    #(
      [types.ValidationError("Int", "String", [])],
      option.Some("my_field"),
      option.Some(value.StringValue("hello")),
      "expected (Int) received (String) value (\"hello\") for (my_field)",
    ),
    // single error with value preview (int)
    #(
      [types.ValidationError("String", "Int", [])],
      option.Some("count"),
      option.Some(value.IntValue(42)),
      "expected (String) received (Int) value (42) for (count)",
    ),
    // single error with value preview (bool)
    #(
      [types.ValidationError("String", "Bool", [])],
      option.Some("flag"),
      option.Some(value.BoolValue(True)),
      "expected (String) received (Bool) value (True) for (flag)",
    ),
  ]
  |> test_helpers.array_based_test_executor_3(
    errors.format_validation_error_message,
  )
}
