//// Type Restrictions:
////
//// Collections:
////   - List(T): T must be a primitive (Boolean, Float, Integer, String)
////   - Dict(K, V): K and V must both be primitives
////
//// Modifiers:
////   - Optional(T): T can be a primitive or collection, not another modifier
////   - Defaulted(T, default): T must be a primitive, default must be valid for T

import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/primitive_types
import gleam/dynamic/decode
import gleam/list

/// Decoder that validates a string references an item in a collection by name.
@internal
pub fn named_reference_decoder(
  collection: List(a),
  name_extraction: fn(a) -> String,
) -> decode.Decoder(String) {
  let names = collection |> list.map(name_extraction)
  let default = Error("")

  decode.new_primitive_decoder("NamedReference", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok(x) -> {
        case names |> list.contains(x) {
          True -> Ok(x)
          False -> default
        }
      }
      _ -> default
    }
  })
}

/// Decoder for non-empty strings. Fails if the string is empty.
@internal
pub fn non_empty_string_decoder() -> decode.Decoder(String) {
  let default = Error("")

  decode.new_primitive_decoder("NonEmptyString", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok("") -> default
      Ok(s) -> Ok(s)
      _ -> default
    }
  })
}

/// Decoder for AcceptedTypes from a string like "Dict(String, String)".
@internal
pub fn accepted_types_decoder() -> decode.Decoder(AcceptedTypes) {
  use raw_string <- decode.then(decode.string)
  case accepted_types.parse_accepted_type(raw_string) {
    Ok(t) -> decode.success(t)
    Error(Nil) ->
      decode.failure(
        accepted_types.PrimitiveType(primitive_types.Boolean),
        "AcceptedType",
      )
  }
}

/// Decoder that converts a dynamic value to its String representation based on type.
/// Delegates to accepted_types.decode_value_to_string.
@internal
pub fn decode_value_to_string(typ: AcceptedTypes) -> decode.Decoder(String) {
  accepted_types.decode_value_to_string(typ)
}

/// Decoder that converts a list of dynamic values to List(String).
/// Delegates to accepted_types.decode_list_values_to_strings.
@internal
pub fn decode_list_values_to_strings(
  inner_type: AcceptedTypes,
) -> decode.Decoder(List(String)) {
  accepted_types.decode_list_values_to_strings(inner_type)
}
