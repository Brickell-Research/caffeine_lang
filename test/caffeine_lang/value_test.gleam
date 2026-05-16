import caffeine_lang/value.{
  BoolValue, Day, DictValue, DurationValue, FloatValue, Hour, IntValue,
  ListValue, Millisecond, Minute, NilValue, PercentageValue, Second, StringValue,
}
import gleam/dict
import test_helpers

// ==== to_string ====
// * ✅ converts string value
// * ✅ converts int value
// * ✅ converts float value
// * ✅ converts percentage value
// * ✅ converts bool value
// * ✅ converts nil value
// * ✅ converts list value
// * ✅ converts dict value
pub fn to_string_test() {
  [
    #("converts string value", StringValue("hello"), "hello"),
    #("converts int value", IntValue(42), "42"),
    #("converts float value", FloatValue(3.14), "3.14"),
    #("converts percentage value", PercentageValue(99.9), "99.9"),
    #("converts bool value", BoolValue(True), "true"),
    #("converts nil value", NilValue, ""),
    #(
      "converts list value",
      ListValue([StringValue("a"), StringValue("b")]),
      "[a, b]",
    ),
    #(
      "converts dict value",
      DictValue(dict.from_list([#("k", StringValue("v"))])),
      "{k: v}",
    ),
    #("converts duration days", DurationValue(10.0, Day), "10.0d"),
    #("converts duration ms", DurationValue(50.0, Millisecond), "50.0ms"),
  ]
  |> test_helpers.table_test_1(value.to_string)
}

// ==== to_preview_string ====
// * ✅ quotes strings
// * ✅ shows numbers directly
// * ✅ shows percentage with suffix
// * ✅ shows Nil for nil
pub fn to_preview_string_test() {
  [
    #("quotes strings", StringValue("hello"), "\"hello\""),
    #("shows int directly", IntValue(42), "42"),
    #("shows float directly", FloatValue(3.14), "3.14"),
    #("shows percentage with suffix", PercentageValue(99.9), "99.9%"),
    #("shows bool directly", BoolValue(True), "true"),
    #("shows Nil for nil", NilValue, "Nil"),
    #("shows List for list", ListValue([]), "List"),
    #("shows Dict for dict", DictValue(dict.new()), "Dict"),
    #("shows duration with suffix", DurationValue(10.0, Day), "10.0d"),
  ]
  |> test_helpers.table_test_1(value.to_preview_string)
}

// ==== classify ====
// * ✅ returns type names
pub fn classify_test() {
  [
    #("classifies string", StringValue("x"), "String"),
    #("classifies int", IntValue(1), "Int"),
    #("classifies float", FloatValue(1.0), "Float"),
    #("classifies percentage", PercentageValue(99.9), "Percentage"),
    #("classifies bool", BoolValue(True), "Bool"),
    #("classifies list", ListValue([]), "List"),
    #("classifies dict", DictValue(dict.new()), "Dict"),
    #("classifies duration", DurationValue(10.0, Day), "Duration"),
    #("classifies nil", NilValue, "Nil"),
  ]
  |> test_helpers.table_test_1(value.classify)
}

// ==== extract_duration ====
// * ✅ extracts from DurationValue
// * ✅ returns Error for non-duration
pub fn extract_duration_test() {
  [
    #("extracts from DurationValue", DurationValue(10.0, Day), Ok(#(10.0, Day))),
    #("returns Error for non-duration", IntValue(10), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_duration)
}

// ==== duration_to_milliseconds ====
// * ✅ ms identity
// * ✅ seconds → ms
// * ✅ minutes → ms
// * ✅ hours → ms
// * ✅ days → ms
// * ✅ sub-second precision
pub fn duration_to_milliseconds_test() {
  [
    #("ms identity", #(50.0, Millisecond), 50.0),
    #("seconds to ms", #(2.0, Second), 2000.0),
    #("minutes to ms", #(5.0, Minute), 300_000.0),
    #("hours to ms", #(1.0, Hour), 3_600_000.0),
    #("days to ms", #(10.0, Day), 864_000_000.0),
    #("sub-second precision", #(0.2, Second), 200.0),
  ]
  |> test_helpers.table_test_1(fn(args: #(Float, value.DurationUnit)) {
    value.duration_to_milliseconds(args.0, args.1)
  })
}

// ==== duration_unit_round_trip ====
// * ✅ each unit round-trips through to_string and from_string
pub fn duration_unit_round_trip_test() {
  [
    #("ms", Millisecond, Ok(Millisecond)),
    #("s", Second, Ok(Second)),
    #("m", Minute, Ok(Minute)),
    #("h", Hour, Ok(Hour)),
    #("d", Day, Ok(Day)),
  ]
  |> test_helpers.table_test_1(fn(unit: value.DurationUnit) {
    value.duration_unit_from_string(value.duration_unit_to_string(unit))
  })
}

// ==== extract_string ====
// * ✅ extracts from StringValue
// * ✅ returns Error for non-string
pub fn extract_string_test() {
  [
    #("extracts from StringValue", StringValue("hello"), Ok("hello")),
    #("returns Error for non-string", IntValue(42), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_string)
}

// ==== extract_int ====
// * ✅ extracts from IntValue
// * ✅ returns Error for non-int
pub fn extract_int_test() {
  [
    #("extracts from IntValue", IntValue(42), Ok(42)),
    #("returns Error for non-int", StringValue("x"), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_int)
}

// ==== extract_float ====
// * ✅ extracts from FloatValue
// * ✅ returns Error for non-float
pub fn extract_float_test() {
  [
    #("extracts from FloatValue", FloatValue(3.14), Ok(3.14)),
    #("returns Error for non-float", IntValue(1), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_float)
}

// ==== extract_percentage ====
// * ✅ extracts from PercentageValue
// * ✅ returns Error for non-percentage
pub fn extract_percentage_test() {
  [
    #("extracts from PercentageValue", PercentageValue(99.9), Ok(99.9)),
    #("returns Error for FloatValue", FloatValue(99.9), Error(Nil)),
    #("returns Error for non-percentage", IntValue(1), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_percentage)
}

// ==== extract_bool ====
// * ✅ extracts from BoolValue
// * ✅ returns Error for non-bool
pub fn extract_bool_test() {
  [
    #("extracts from BoolValue", BoolValue(True), Ok(True)),
    #("returns Error for non-bool", StringValue("x"), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_bool)
}

// ==== extract_dict ====
// * ✅ extracts from DictValue
// * ✅ returns Error for non-dict
pub fn extract_dict_test() {
  let d = dict.from_list([#("k", StringValue("v"))])
  [
    #("extracts from DictValue", DictValue(d), Ok(d)),
    #("returns Error for non-dict", StringValue("x"), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_dict)
}

// ==== extract_string_dict ====
// * ✅ extracts string dict from DictValue with string values
// * ✅ returns Error for DictValue with non-string values
// * ✅ returns Error for non-dict
pub fn extract_string_dict_test() {
  [
    #(
      "extracts string dict from DictValue with string values",
      DictValue(dict.from_list([#("k", StringValue("v"))])),
      Ok(dict.from_list([#("k", "v")])),
    ),
    #(
      "returns Error for DictValue with non-string values",
      DictValue(dict.from_list([#("k", IntValue(1))])),
      Error(Nil),
    ),
    #("returns Error for non-dict", StringValue("x"), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_string_dict)
}
