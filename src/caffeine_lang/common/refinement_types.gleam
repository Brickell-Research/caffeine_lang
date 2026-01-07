import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
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
  ///   * Primitives: Integer
  /// 
  /// Furthermore, we initially will only support an inclusive
  /// range, as noted in the type name here.
  InclusiveRange(accepted, Int, Int)
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
      <> " { x | x in { ("
      <> int.to_string(low)
      <> ".."
      <> int.to_string(high)
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
      case int.parse(as_str) {
        Ok(int_val) -> {
          case int_val >= low, int_val <= high {
            True, True -> Ok(value)
            False, _ ->
              Error([
                decode.DecodeError(
                  expected: " > " <> int.to_string(low),
                  found: as_str,
                  path: [],
                ),
              ])
            _, False ->
              Error([
                decode.DecodeError(
                  expected: " < " <> int.to_string(high),
                  found: as_str,
                  path: [],
                ),
              ])
          }
        }
        Error(_) ->
          Error([
            decode.DecodeError(expected: "Ineger", found: as_str, path: []),
          ])
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
  // Expect exact format: " x | x in { ... } }" (with leading space from split)
  case raw {
    " x | x in { " <> rest_rest -> {
      // Must end with " } }" (inner closing brace, space, outer closing brace)
      case string.ends_with(rest_rest, " } }") {
        True -> {
          // Remove the trailing " } }" to get just the values
          let set_vals =
            rest_rest
            |> string.drop_end(4)
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
    " x | x in ( " <> rest_rest -> {
      // InclusiveRange only supports Integer primitive, not Defaulted or other types
      case raw_typ {
        "Integer" -> {
          // Must end with " ) }" (inner closing paren, space, outer closing brace)
          case string.ends_with(rest_rest, " ) }") {
            True -> {
              // Remove the trailing " ) }" to get just the values
              let low_high_vals =
                rest_rest
                |> string.drop_end(4)
              let values =
                low_high_vals
                |> string.split("..")
                |> list.map(string.trim)
                |> list.filter(fn(s) { s != "" })
              case values {
                [] -> Error(Nil)
                _ -> {
                  // Validate all values are valid for the type
                  case list.try_each(values, validate_set_value(typ, _)) {
                    Ok(_) -> {
                      case values |> list.map(int.parse) {
                        [Ok(low), Ok(high)] if low <= high ->
                          Ok(InclusiveRange(typ, low, high))
                        _ -> Error(Nil)
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
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}
