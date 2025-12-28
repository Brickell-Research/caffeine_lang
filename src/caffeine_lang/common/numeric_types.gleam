import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/result

/// NumericTypes are just _numbers_ which have a variety of representations.
pub type NumericTypes {
  Float
  Integer
}

/// Converts a NumericTypes to its string representation.
pub fn numeric_type_to_string(numeric_type: NumericTypes) -> String {
  case numeric_type {
    Float -> "Float"
    Integer -> "Integer"
  }
}

/// Parses a string into a NumericTypes.
@internal
pub fn parse_numeric_type(raw: String) -> Result(NumericTypes, Nil) {
  case raw {
    "Float" -> Ok(Float)
    "Integer" -> Ok(Integer)
    _ -> Error(Nil)
  }
}

/// Decoder that converts a dynamic numeric value to its String representation.
@internal
pub fn decode_numeric_to_string(numeric: NumericTypes) -> decode.Decoder(String) {
  case numeric {
    Float -> {
      use val <- decode.then(decode.float)
      decode.success(float.to_string(val))
    }
    Integer -> {
      use val <- decode.then(decode.int)
      decode.success(int.to_string(val))
    }
  }
}

/// Validates a default value is compatible with the numeric type.
@internal
pub fn validate_default_value(
  numeric: NumericTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  case numeric {
    Integer -> int.parse(default_val) |> result.replace(Nil)
    Float -> float.parse(default_val) |> result.replace(Nil)
  }
}

/// Validates a dynamic value matches the numeric type.
@internal
pub fn validate_value(
  numeric: NumericTypes,
  value: Dynamic,
) -> Result(Dynamic, List(decode.DecodeError)) {
  let decoder = case numeric {
    Integer -> decode.int |> decode.map(fn(_) { value })
    Float -> decode.float |> decode.map(fn(_) { value })
  }
  decode.run(value, decoder)
}
