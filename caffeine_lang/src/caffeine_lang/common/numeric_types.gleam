import caffeine_lang/common/type_info.{type TypeMeta, TypeMeta}
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

/// Returns metadata for all NumericTypes variants.
/// IMPORTANT: Update this when adding new variants!
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  [numeric_type_meta(Integer), numeric_type_meta(Float)]
}

/// Returns metadata for a NumericTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
@internal
pub fn numeric_type_meta(typ: NumericTypes) -> TypeMeta {
  case typ {
    Integer ->
      TypeMeta(
        name: "Integer",
        description: "Whole numbers",
        syntax: "Integer",
        example: "42, 0, -10",
      )
    Float ->
      TypeMeta(
        name: "Float",
        description: "Decimal numbers",
        syntax: "Float",
        example: "3.14, 99.9, 0.0",
      )
  }
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
  parse_string(numeric, default_val) |> result.replace(Nil)
}

fn parse_string(numeric: NumericTypes, value: String) -> Result(Float, Nil) {
  case numeric {
    Integer -> int.parse(value) |> result.map(int.to_float)
    Float -> float.parse(value)
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

/// Validates a string value is within an inclusive range for the given numeric type.
@internal
pub fn validate_in_range(
  numeric: NumericTypes,
  value_str: String,
  low_str: String,
  high_str: String,
) -> Result(Nil, List(decode.DecodeError)) {
  let type_name = numeric_type_to_string(numeric)
  case
    parse_string(numeric, value_str),
    parse_string(numeric, low_str),
    parse_string(numeric, high_str)
  {
    Ok(val), Ok(low), Ok(high) -> {
      case val >=. low, val <=. high {
        True, True -> Ok(Nil)
        _, _ ->
          Error([
            decode.DecodeError(
              expected: low_str <> " <= x <= " <> high_str,
              found: value_str,
              path: [],
            ),
          ])
      }
    }
    _, _, _ ->
      Error([
        decode.DecodeError(expected: type_name, found: value_str, path: []),
      ])
  }
}
