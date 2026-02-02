import caffeine_lang/value.{
  BoolValue, DictValue, FloatValue, IntValue, ListValue, NilValue, StringValue,
}
import gleam/dict
import gleeunit/should

// ==== to_string ====
// * ✅ converts string value
// * ✅ converts int value
// * ✅ converts float value
// * ✅ converts bool value
// * ✅ converts nil value
// * ✅ converts list value
// * ✅ converts dict value
pub fn to_string_test() {
  StringValue("hello") |> value.to_string |> should.equal("hello")
  IntValue(42) |> value.to_string |> should.equal("42")
  FloatValue(3.14) |> value.to_string |> should.equal("3.14")
  BoolValue(True) |> value.to_string |> should.equal("True")
  NilValue |> value.to_string |> should.equal("")
  ListValue([StringValue("a"), StringValue("b")])
  |> value.to_string
  |> should.equal("[a, b]")
  DictValue(dict.from_list([#("k", StringValue("v"))]))
  |> value.to_string
  |> should.equal("{k: v}")
}

// ==== to_preview_string ====
// * ✅ quotes strings
// * ✅ shows numbers directly
// * ✅ shows Nil for nil
pub fn to_preview_string_test() {
  StringValue("hello") |> value.to_preview_string |> should.equal("\"hello\"")
  IntValue(42) |> value.to_preview_string |> should.equal("42")
  FloatValue(3.14) |> value.to_preview_string |> should.equal("3.14")
  BoolValue(True) |> value.to_preview_string |> should.equal("True")
  NilValue |> value.to_preview_string |> should.equal("Nil")
  ListValue([]) |> value.to_preview_string |> should.equal("List")
  DictValue(dict.new()) |> value.to_preview_string |> should.equal("Dict")
}

// ==== classify ====
// * ✅ returns type names
pub fn classify_test() {
  StringValue("x") |> value.classify |> should.equal("String")
  IntValue(1) |> value.classify |> should.equal("Int")
  FloatValue(1.0) |> value.classify |> should.equal("Float")
  BoolValue(True) |> value.classify |> should.equal("Bool")
  ListValue([]) |> value.classify |> should.equal("List")
  DictValue(dict.new()) |> value.classify |> should.equal("Dict")
  NilValue |> value.classify |> should.equal("Nil")
}

// ==== extract_string ====
// * ✅ extracts from StringValue
// * ✅ returns Error for non-string
pub fn extract_string_test() {
  StringValue("hello") |> value.extract_string |> should.equal(Ok("hello"))
  IntValue(42) |> value.extract_string |> should.equal(Error(Nil))
}

// ==== extract_int ====
// * ✅ extracts from IntValue
// * ✅ returns Error for non-int
pub fn extract_int_test() {
  IntValue(42) |> value.extract_int |> should.equal(Ok(42))
  StringValue("x") |> value.extract_int |> should.equal(Error(Nil))
}

// ==== extract_float ====
// * ✅ extracts from FloatValue
// * ✅ returns Error for non-float
pub fn extract_float_test() {
  FloatValue(3.14) |> value.extract_float |> should.equal(Ok(3.14))
  IntValue(1) |> value.extract_float |> should.equal(Error(Nil))
}

// ==== extract_bool ====
// * ✅ extracts from BoolValue
// * ✅ returns Error for non-bool
pub fn extract_bool_test() {
  BoolValue(True) |> value.extract_bool |> should.equal(Ok(True))
  StringValue("x") |> value.extract_bool |> should.equal(Error(Nil))
}

// ==== extract_list ====
// * ✅ extracts from ListValue
// * ✅ returns Error for non-list
pub fn extract_list_test() {
  ListValue([IntValue(1)])
  |> value.extract_list
  |> should.equal(Ok([IntValue(1)]))
  StringValue("x") |> value.extract_list |> should.equal(Error(Nil))
}

// ==== extract_dict ====
// * ✅ extracts from DictValue
// * ✅ returns Error for non-dict
pub fn extract_dict_test() {
  let d = dict.from_list([#("k", StringValue("v"))])
  DictValue(d) |> value.extract_dict |> should.equal(Ok(d))
  StringValue("x") |> value.extract_dict |> should.equal(Error(Nil))
}

// ==== extract_string_dict ====
// * ✅ extracts string dict from DictValue with string values
// * ✅ returns Error for DictValue with non-string values
// * ✅ returns Error for non-dict
pub fn extract_string_dict_test() {
  DictValue(dict.from_list([#("k", StringValue("v"))]))
  |> value.extract_string_dict
  |> should.equal(Ok(dict.from_list([#("k", "v")])))

  DictValue(dict.from_list([#("k", IntValue(1))]))
  |> value.extract_string_dict
  |> should.equal(Error(Nil))

  StringValue("x") |> value.extract_string_dict |> should.equal(Error(Nil))
}

// ==== is_nil ====
// * ✅ returns True for NilValue
// * ✅ returns False for other values
pub fn is_nil_test() {
  NilValue |> value.is_nil |> should.be_true
  StringValue("x") |> value.is_nil |> should.be_false
}
