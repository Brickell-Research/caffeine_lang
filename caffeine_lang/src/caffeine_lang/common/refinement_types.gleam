import caffeine_lang/common/numeric_types
import caffeine_lang/common/type_info.{type TypeMeta, TypeMeta}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// Refinement types enforce additional compile-time validations.
pub type RefinementTypes(accepted) {
  /// Restricts values to a user-defined set.
  /// I.E. String { x | x in { pasta, pizza, salad } }
  ///
  /// At this time we only support:
  ///   * Primitives: Integer, Float, String
  ///   * Modifiers:  Defaulted with Integer, Float, String
  OneOf(accepted, set.Set(String))
  /// Restricts values to a user-defined range.
  /// I.E. Int { x | x in (0..100) }
  ///
  /// At this time we only support:
  ///   * Primitives: Integer, Float
  ///
  /// Furthermore, we initially will only support an inclusive
  /// range, as noted in the type name here.
  InclusiveRange(accepted, String, String)
}

/// Returns metadata for all RefinementTypes variants.
/// IMPORTANT: Update this when adding new variants!
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  [
    refinement_type_meta(OneOf(Nil, set.new())),
    refinement_type_meta(InclusiveRange(Nil, "", "")),
  ]
}

/// Returns metadata for a RefinementTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
fn refinement_type_meta(typ: RefinementTypes(accepted)) -> TypeMeta {
  case typ {
    OneOf(_, _) ->
      TypeMeta(
        name: "OneOf",
        description: "Value must be one of a finite set",
        syntax: "T { x | x in { val1, val2, ... } }",
        example: "String { x | x in { datadog, prometheus } }",
      )
    InclusiveRange(_, _, _) ->
      TypeMeta(
        name: "InclusiveRange",
        description: "Value must be within a numeric range (inclusive)",
        syntax: "T { x | x in ( low..high ) }",
        example: "Integer { x | x in ( 0..100 ) }",
      )
  }
}

/// Converts a RefinementTypes to its string representation.
@internal
pub fn refinement_type_to_string(
  refinement: RefinementTypes(accepted),
  accepted_type_to_string: fn(accepted) -> String,
) -> String {
  case refinement {
    OneOf(typ, set_vals) ->
      accepted_type_to_string(typ)
      <> " { x | x in { "
      <> set_vals
      |> set.to_list
      |> list.sort(string.compare)
      |> string.join(", ")
      <> " } }"
    InclusiveRange(typ, low, high) ->
      accepted_type_to_string(typ)
      <> " { x | x in ( "
      <> low
      <> ".."
      <> high
      <> " ) }"
  }
}

/// Parses a string into a RefinementTypes.
/// Returns the parsed refinement type with its inner types parsed using the provided function.
/// The validate_set_value function validates that each value in the set is valid for the type.
@internal
pub fn parse_refinement_type(
  raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
  validate_set_value: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(RefinementTypes(accepted), Nil) {
  case raw |> string.split_once("{") {
    Ok(#(typ, rest)) -> {
      let trimmed_typ = typ |> string.trim
      case trimmed_typ {
        // TODO: fix, this is terrible
        "Boolean" | "Dict" | "List" | "Optional" -> Error(Nil)
        _ -> {
          use parsed_typ <- result.try(parse_inner(trimmed_typ))
          do_parse_refinement(parsed_typ, trimmed_typ, rest, validate_set_value)
        }
      }
    }
    _ -> Error(Nil)
  }
}

/// Decoder for refinement types.
@internal
pub fn decode_refinement_to_string(
  _collection: RefinementTypes(accepted),
  _decode_inner: fn(accepted) -> decode.Decoder(String),
) -> decode.Decoder(String) {
  decode.failure("", "RefinementType")
}

/// Validates a dynamic value matches the refinement type.
/// Returns the original value if valid, or an error with decode errors.
@internal
pub fn validate_value(
  refinement: RefinementTypes(accepted),
  value: Dynamic,
  decode_inner_to_string: fn(accepted) -> decode.Decoder(String),
  get_numeric_type: fn(accepted) -> numeric_types.NumericTypes,
) -> Result(Dynamic, List(decode.DecodeError)) {
  case refinement {
    OneOf(inner_type, allowed_values) -> {
      case decode.run(value, decode_inner_to_string(inner_type)) {
        Ok(str_val) -> {
          case set.contains(allowed_values, str_val) {
            True -> Ok(value)
            False ->
              Error([
                decode.DecodeError(
                  expected: "one of: "
                    <> allowed_values
                  |> set.to_list
                  |> list.sort(string.compare)
                  |> string.join(", "),
                  found: str_val,
                  path: [],
                ),
              ])
          }
        }
        Error(errs) -> Error(errs)
      }
    }

    InclusiveRange(inner_type, low, high) -> {
      use as_str <- result.try(decode.run(
        value,
        decode_inner_to_string(inner_type),
      ))
      let numeric = get_numeric_type(inner_type)
      case numeric_types.validate_in_range(numeric, as_str, low, high) {
        Ok(_) -> Ok(value)
        Error(errs) -> Error(errs)
      }
    }
  }
}

/// Resolves a refinement value to a string using the provided resolver functions.
/// Since we've already validated that this is valid and we only thus far support a
/// subset of primitives for OneOf, we just have to decode the value based on our
/// inner type.
@internal
pub fn resolve_to_string(
  refinement: RefinementTypes(accepted),
  value: Dynamic,
  decode_inner_to_string: fn(accepted) -> decode.Decoder(String),
  resolve_string: fn(String) -> String,
) -> Result(String, String) {
  case refinement {
    OneOf(inner_type, _allowed_values) -> {
      case decode.run(value, decode_inner_to_string(inner_type)) {
        Ok(val) -> Ok(resolve_string(val))
        Error(_) -> Error("Unable to decode OneOf refinement type value.")
      }
    }
    InclusiveRange(inner_type, _low, _high) -> {
      case decode.run(value, decode_inner_to_string(inner_type)) {
        Ok(val) -> Ok(resolve_string(val))
        Error(_) ->
          Error("Unable to decode InclusiveRange refinement type value.")
      }
    }
  }
}

fn do_parse_refinement(
  typ: accepted,
  raw_typ: String,
  raw: String,
  validate_set_value: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(RefinementTypes(accepted), Nil) {
  // Expect format: " x | x in { ... } }" or " x | x in ( ... ) }"
  // Spacing between letters/words is required (x | x in), but spacing around symbols is flexible
  // So "{x" is ok, "x|" is ok, but "xin" is not ok (both are words)
  let trimmed = string.trim(raw)
  case normalize_refinement_guard(trimmed) {
    Ok(#("x | x in", rest)) -> {
      let rest_trimmed = string.trim(rest)
      case rest_trimmed {
        "{" <> values_rest -> parse_one_of(typ, values_rest, validate_set_value)
        "(" <> values_rest ->
          parse_inclusive_range(typ, raw_typ, values_rest, validate_set_value)
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Normalizes the refinement guard syntax, allowing flexible spacing around symbols.
/// Returns the normalized guard and the remaining string after it.
/// Valid: "x | x in", "x| x in", "x |x in", "x|x in" (flexible around |)
/// Invalid: "xin" (no space between words)
fn normalize_refinement_guard(raw: String) -> Result(#(String, String), Nil) {
  // Pattern: x (optional space) | (optional space) x (required space) in (rest)
  case raw {
    "x | x in" <> rest -> Ok(#("x | x in", rest))
    "x| x in" <> rest -> Ok(#("x | x in", rest))
    "x |x in" <> rest -> Ok(#("x | x in", rest))
    "x|x in" <> rest -> Ok(#("x | x in", rest))
    _ -> Error(Nil)
  }
}

fn parse_one_of(
  typ: accepted,
  raw: String,
  validate_set_value: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(RefinementTypes(accepted), Nil) {
  // Must end with "} }" (inner closing brace, space, outer closing brace)
  // But there may or may not be a space before the inner closing brace
  case string.ends_with(raw, "} }") {
    True -> {
      // Remove the trailing "} }" and trim to get just the values
      let set_vals =
        raw
        |> string.drop_end(3)
        |> string.trim
      let values =
        set_vals
        |> string.split(",")
        |> list.map(string.trim)
        |> list.filter(fn(s) { s != "" })
      case values {
        [] -> Error(Nil)
        _ -> {
          // Validate all values are valid for the type
          case list.try_each(values, validate_set_value(typ, _)) {
            Ok(_) -> {
              let value_set = set.from_list(values)
              // Ensure no duplicate values (set size must match list length)
              case set.size(value_set) == list.length(values) {
                True -> Ok(OneOf(typ, value_set))
                False -> Error(Nil)
              }
            }
            Error(_) -> Error(Nil)
          }
        }
      }
    }
    False -> Error(Nil)
  }
}

fn parse_inclusive_range(
  typ: accepted,
  raw_typ: String,
  raw: String,
  validate_set_value: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(RefinementTypes(accepted), Nil) {
  // InclusiveRange only supports Integer/Float primitives, not Defaulted or other types
  case raw_typ {
    "Integer" | "Float" -> {
      // Must end with ") }" (inner closing paren, space, outer closing brace)
      // But there may or may not be a space before the inner closing paren
      case string.ends_with(raw, ") }") {
        True -> {
          // Remove the trailing ") }" and trim to get just the values
          let low_high_vals =
            raw
            |> string.drop_end(3)
            |> string.trim
          let values =
            low_high_vals
            |> string.split("..")
            |> list.map(string.trim)
            |> list.filter(fn(s) { s != "" })
          case values {
            [] -> Error(Nil)
            [low, high] -> {
              // Validate all values are valid for the type
              case list.try_each(values, validate_set_value(typ, _)) {
                Ok(_) -> {
                  // Validate bounds based on type and ensure low <= high
                  case validate_bounds_order(raw_typ, low, high) {
                    Ok(_) -> Ok(InclusiveRange(typ, low, high))
                    Error(_) -> Error(Nil)
                  }
                }
                Error(_) -> Error(Nil)
              }
            }
            _ -> Error(Nil)
          }
        }
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Validates that bounds are in valid order (low <= high) for a numeric type.
fn validate_bounds_order(
  raw_typ: String,
  low: String,
  high: String,
) -> Result(Nil, Nil) {
  case numeric_types.parse_numeric_type(raw_typ) {
    Ok(numeric) ->
      numeric_types.validate_in_range(numeric, low, low, high)
      |> result.replace_error(Nil)
    Error(Nil) -> Error(Nil)
  }
}
