import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// A typed value ADT that carries type information forward through the pipeline.
/// Replaces the use of Dynamic for values in the compiler pipeline.
pub type Value {
  StringValue(String)
  IntValue(Int)
  FloatValue(Float)
  BoolValue(Bool)
  ListValue(List(Value))
  DictValue(Dict(String, Value))
  /// Represents an absent Optional or Defaulted value.
  NilValue
}

/// Converts a Value to its string representation for template resolution.
@internal
pub fn to_string(value: Value) -> String {
  case value {
    StringValue(s) -> s
    IntValue(i) -> int.to_string(i)
    FloatValue(f) -> float.to_string(f)
    BoolValue(b) -> bool.to_string(b)
    ListValue(items) ->
      "[" <> items |> list.map(to_string) |> string.join(", ") <> "]"
    DictValue(d) ->
      "{"
      <> d
      |> dict.to_list
      |> list.map(fn(pair) { pair.0 <> ": " <> to_string(pair.1) })
      |> string.join(", ")
      <> "}"
    NilValue -> ""
  }
}

/// Converts a Value to a short preview string for error messages.
@internal
pub fn to_preview_string(value: Value) -> String {
  case value {
    StringValue(s) -> "\"" <> s <> "\""
    IntValue(i) -> int.to_string(i)
    FloatValue(f) -> float.to_string(f)
    BoolValue(b) -> bool.to_string(b)
    ListValue(_) -> "List"
    DictValue(_) -> "Dict"
    NilValue -> "Nil"
  }
}

/// Returns a type name string for a Value, useful for error messages.
@internal
pub fn classify(value: Value) -> String {
  case value {
    StringValue(_) -> "String"
    IntValue(_) -> "Int"
    FloatValue(_) -> "Float"
    BoolValue(_) -> "Bool"
    ListValue(_) -> "List"
    DictValue(_) -> "Dict"
    NilValue -> "Nil"
  }
}

/// Extracts a String from a Value, returning Error if not a StringValue.
@internal
pub fn extract_string(value: Value) -> Result(String, Nil) {
  case value {
    StringValue(s) -> Ok(s)
    _ -> Error(Nil)
  }
}

/// Extracts an Int from a Value, returning Error if not an IntValue.
@internal
pub fn extract_int(value: Value) -> Result(Int, Nil) {
  case value {
    IntValue(i) -> Ok(i)
    _ -> Error(Nil)
  }
}

/// Extracts a Float from a Value, returning Error if not a FloatValue.
@internal
pub fn extract_float(value: Value) -> Result(Float, Nil) {
  case value {
    FloatValue(f) -> Ok(f)
    _ -> Error(Nil)
  }
}

/// Extracts a Bool from a Value, returning Error if not a BoolValue.
@internal
pub fn extract_bool(value: Value) -> Result(Bool, Nil) {
  case value {
    BoolValue(b) -> Ok(b)
    _ -> Error(Nil)
  }
}

/// Extracts a List from a Value, returning Error if not a ListValue.
@internal
pub fn extract_list(value: Value) -> Result(List(Value), Nil) {
  case value {
    ListValue(l) -> Ok(l)
    _ -> Error(Nil)
  }
}

/// Extracts a Dict from a Value, returning Error if not a DictValue.
@internal
pub fn extract_dict(value: Value) -> Result(Dict(String, Value), Nil) {
  case value {
    DictValue(d) -> Ok(d)
    _ -> Error(Nil)
  }
}

/// Extracts a Dict(String, String) from a Value.
/// Returns Error if not a DictValue or if any value is not a StringValue.
@internal
pub fn extract_string_dict(value: Value) -> Result(Dict(String, String), Nil) {
  case value {
    DictValue(d) ->
      d
      |> dict.to_list
      |> list.try_map(fn(pair) {
        case pair.1 {
          StringValue(s) -> Ok(#(pair.0, s))
          _ -> Error(Nil)
        }
      })
      |> result.map(dict.from_list)
    _ -> Error(Nil)
  }
}

/// Checks if a Value is NilValue.
@internal
pub fn is_nil(value: Value) -> Bool {
  case value {
    NilValue -> True
    _ -> False
  }
}
