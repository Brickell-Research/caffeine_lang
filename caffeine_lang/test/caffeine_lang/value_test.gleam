import caffeine_lang/value.{
  BoolValue, DictValue, FloatValue, IntValue, ListValue, NilValue, StringValue,
}
import gleam/dict
import test_helpers

// ==== to_string ====
// * ✅ converts string value
// * ✅ converts int value
// * ✅ converts float value
// * ✅ converts bool value
// * ✅ converts nil value
// * ✅ converts list value
// * ✅ converts dict value
pub fn to_string_test() {
  [
    #("converts string value", StringValue("hello"), "hello"),
    #("converts int value", IntValue(42), "42"),
    #("converts float value", FloatValue(3.14), "3.14"),
    #("converts bool value", BoolValue(True), "True"),
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
  ]
  |> test_helpers.table_test_1(value.to_string)
}

// ==== to_preview_string ====
// * ✅ quotes strings
// * ✅ shows numbers directly
// * ✅ shows Nil for nil
pub fn to_preview_string_test() {
  [
    #("quotes strings", StringValue("hello"), "\"hello\""),
    #("shows int directly", IntValue(42), "42"),
    #("shows float directly", FloatValue(3.14), "3.14"),
    #("shows bool directly", BoolValue(True), "True"),
    #("shows Nil for nil", NilValue, "Nil"),
    #("shows List for list", ListValue([]), "List"),
    #("shows Dict for dict", DictValue(dict.new()), "Dict"),
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
    #("classifies bool", BoolValue(True), "Bool"),
    #("classifies list", ListValue([]), "List"),
    #("classifies dict", DictValue(dict.new()), "Dict"),
    #("classifies nil", NilValue, "Nil"),
  ]
  |> test_helpers.table_test_1(value.classify)
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

// ==== extract_list ====
// * ✅ extracts from ListValue
// * ✅ returns Error for non-list
pub fn extract_list_test() {
  [
    #("extracts from ListValue", ListValue([IntValue(1)]), Ok([IntValue(1)])),
    #("returns Error for non-list", StringValue("x"), Error(Nil)),
  ]
  |> test_helpers.table_test_1(value.extract_list)
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

// ==== is_nil ====
// * ✅ returns True for NilValue
// * ✅ returns False for other values
pub fn is_nil_test() {
  [
    #("returns True for NilValue", NilValue, True),
    #("returns False for other values", StringValue("x"), False),
  ]
  |> test_helpers.table_test_1(value.is_nil)
}
