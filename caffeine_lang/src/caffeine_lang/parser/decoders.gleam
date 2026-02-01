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
import gleam/string

/// Decoder that validates a string references an item in a collection by name.
@internal
pub fn named_reference_decoder(
  from collection: List(a),
  by name_extraction: fn(a) -> String,
) -> decode.Decoder(String) {
  let names = collection |> list.map(name_extraction)
  let default = Error("")

  let expected_name =
    "NamedReference (one of: " <> string.join(names, ", ") <> ")"
  decode.new_primitive_decoder(expected_name, fn(dyn) {
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

/// Decoder for a non-empty list of named references.
/// Each element must be a string that references an item in the collection.
@internal
pub fn non_empty_named_reference_list_decoder(
  from collection: List(a),
  by name_extraction: fn(a) -> String,
) -> decode.Decoder(List(String)) {
  let inner_decoder =
    named_reference_decoder(from: collection, by: name_extraction)

  // Decode as a list first, then validate non-empty
  use refs <- decode.then(decode.list(inner_decoder))
  case refs {
    [] -> decode.failure([], "NonEmptyList")
    _ -> decode.success(refs)
  }
}

/// Decoder for non-empty strings. Fails if the string is empty.
@internal
pub fn non_empty_string_decoder() -> decode.Decoder(String) {
  use str <- decode.then(decode.string)
  case str {
    "" -> decode.failure("", "NonEmptyString (got empty string)")
    s -> decode.success(s)
  }
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
        "AcceptedType (unknown: " <> raw_string <> ")",
      )
  }
}
