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
  PercentageValue(Float)
  BoolValue(Bool)
  ListValue(List(Value))
  DictValue(Dict(String, Value))
  /// A duration literal such as `10d`, `50ms`, `0.200s`.
  /// `amount` is the as-written magnitude; `unit` the as-written suffix.
  /// Use `duration_to_milliseconds` for unit-normalized comparison.
  DurationValue(amount: Float, unit: DurationUnit)
  /// Represents an absent Optional or Defaulted value.
  NilValue
}

/// Unit suffix on a duration literal. Round-trippable with `duration_unit_to_string`.
pub type DurationUnit {
  Millisecond
  Second
  Minute
  Hour
  Day
}

/// Renders a duration unit back to its source-syntax suffix.
@internal
pub fn duration_unit_to_string(unit: DurationUnit) -> String {
  case unit {
    Millisecond -> "ms"
    Second -> "s"
    Minute -> "m"
    Hour -> "h"
    Day -> "d"
  }
}

/// Parses a duration unit suffix string back into the typed enum.
@internal
pub fn duration_unit_from_string(raw: String) -> Result(DurationUnit, Nil) {
  case raw {
    "ms" -> Ok(Millisecond)
    "s" -> Ok(Second)
    "m" -> Ok(Minute)
    "h" -> Ok(Hour)
    "d" -> Ok(Day)
    _ -> Error(Nil)
  }
}

/// Normalizes a duration value to milliseconds. Used for unit-agnostic comparison.
@internal
pub fn duration_to_milliseconds(amount: Float, unit: DurationUnit) -> Float {
  case unit {
    Millisecond -> amount
    Second -> amount *. 1000.0
    Minute -> amount *. 60_000.0
    Hour -> amount *. 3_600_000.0
    Day -> amount *. 86_400_000.0
  }
}

/// Converts a Value to its string representation for template resolution.
@internal
pub fn to_string(value: Value) -> String {
  case value {
    StringValue(s) -> s
    IntValue(i) -> int.to_string(i)
    FloatValue(f) -> float.to_string(f)
    PercentageValue(f) -> float.to_string(f)
    BoolValue(True) -> "true"
    BoolValue(False) -> "false"
    ListValue(items) ->
      "[" <> items |> list.map(to_string) |> string.join(", ") <> "]"
    DictValue(d) ->
      "{"
      <> d
      |> dict.to_list
      |> list.map(fn(pair) { pair.0 <> ": " <> to_string(pair.1) })
      |> string.join(", ")
      <> "}"
    DurationValue(amount, unit) ->
      float.to_string(amount) <> duration_unit_to_string(unit)
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
    PercentageValue(f) -> float.to_string(f) <> "%"
    BoolValue(True) -> "true"
    BoolValue(False) -> "false"
    ListValue(_) -> "List"
    DictValue(_) -> "Dict"
    DurationValue(amount, unit) ->
      float.to_string(amount) <> duration_unit_to_string(unit)
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
    PercentageValue(_) -> "Percentage"
    BoolValue(_) -> "Bool"
    ListValue(_) -> "List"
    DictValue(_) -> "Dict"
    DurationValue(_, _) -> "Duration"
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

/// Extracts a Float from a PercentageValue, returning Error otherwise.
@internal
pub fn extract_percentage(value: Value) -> Result(Float, Nil) {
  case value {
    PercentageValue(f) -> Ok(f)
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

/// Extracts a duration's amount and unit, returning Error if not a DurationValue.
@internal
pub fn extract_duration(value: Value) -> Result(#(Float, DurationUnit), Nil) {
  case value {
    DurationValue(amount, unit) -> Ok(#(amount, unit))
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
