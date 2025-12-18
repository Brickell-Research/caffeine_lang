//// Type Restrictions:
////
//// Collections:
////   - List(T): T must be a primitive (Boolean, Float, Integer, String)
////   - Dict(K, V): K and V must both be primitives
////
//// Modifiers:
////   - Optional(T): T can be a primitive or collection, not another modifier
////   - Defaulted(T, default): T must be a primitive, default must be valid for T

import caffeine_lang/common/accepted_types.{
  type AcceptedTypes, Boolean, CollectionType, Defaulted, Dict, Float, Integer,
  List, ModifierType, Optional, PrimitiveType, String,
}
import gleam/bool
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

/// Decoder that validates a string references an item in a collection by name.
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
pub fn accepted_types_decoder() -> decode.Decoder(AcceptedTypes) {
  use raw_string <- decode.then(decode.string)
  case parse_accepted_type(raw_string) {
    Ok(t) -> decode.success(t)
    Error(Nil) -> decode.failure(PrimitiveType(Boolean), "AcceptedType")
  }
}

/// Decoder that converts a dynamic value to its String representation based on type.
pub fn decode_value_to_string(typ: AcceptedTypes) -> decode.Decoder(String) {
  case typ {
    PrimitiveType(primitive) ->
      case primitive {
        Boolean -> {
          use val <- decode.then(decode.bool)
          decode.success(bool.to_string(val))
        }
        Float -> {
          use val <- decode.then(decode.float)
          decode.success(float.to_string(val))
        }
        Integer -> {
          use val <- decode.then(decode.int)
          decode.success(int.to_string(val))
        }
        String -> decode.string
      }
    CollectionType(collection) ->
      case collection {
        Dict(_, _) -> decode.failure("", "Dict")
        List(_) -> decode.failure("", "List")
      }
    ModifierType(modifier) ->
      case modifier {
        Optional(inner_type) -> {
          use maybe_val <- decode.then(
            decode.optional(decode_value_to_string(inner_type)),
          )
          decode.success(option.unwrap(maybe_val, ""))
        }
        Defaulted(inner_type, default_val) -> {
          use maybe_val <- decode.then(
            decode.optional(decode_value_to_string(inner_type)),
          )
          decode.success(option.unwrap(maybe_val, default_val))
        }
      }
  }
}

/// Decoder that converts a list of dynamic values to List(String).
pub fn decode_list_values_to_strings(
  inner_type: AcceptedTypes,
) -> decode.Decoder(List(String)) {
  decode.list(decode_value_to_string(inner_type))
}

/// Parses a string into an AcceptedTypes.
fn parse_accepted_type(raw_accepted_type: String) -> Result(AcceptedTypes, Nil) {
  [
    parse_primitive_typpe,
    parse_collection_type,
    parse_modifier_type,
  ]
  |> list.find_map(fn(parser) { parser(raw_accepted_type) })
}

fn parse_primitive_typpe(raw: String) -> Result(AcceptedTypes, Nil) {
  case raw {
    "Boolean" -> Ok(PrimitiveType(Boolean))
    "Float" -> Ok(PrimitiveType(Float))
    "Integer" -> Ok(PrimitiveType(Integer))
    "String" -> Ok(PrimitiveType(String))
    _ -> Error(Nil)
  }
}

fn parse_collection_type(raw: String) -> Result(AcceptedTypes, Nil) {
  case raw {
    "List" <> inside -> parse_list_type(inside)
    "Dict" <> inside -> parse_dict_type(inside)
    _ -> Error(Nil)
  }
}

/// Parses "(PrimitiveType)" into a List collection type.
fn parse_list_type(inner_raw: String) -> Result(AcceptedTypes, Nil) {
  case
    inner_raw
    |> paren_innerds_trimmed
    |> parse_accepted_type
  {
    Ok(PrimitiveType(primitive)) ->
      Ok(CollectionType(List(PrimitiveType(primitive))))
    _ -> Error(Nil)
  }
}

fn parse_modifier_type(raw: String) -> Result(AcceptedTypes, Nil) {
  case raw {
    "Optional" <> rest -> parse_optional_modifier_type(rest)
    "Defaulted" <> rest -> parse_defaulted_type_two(rest)
    _ -> Error(Nil)
  }
}

fn parse_optional_modifier_type(raw: String) -> Result(AcceptedTypes, Nil) {
  case
    raw
    |> paren_innerds_trimmed
    |> parse_accepted_type
  {
    Ok(PrimitiveType(inner_value)) ->
      Ok(ModifierType(Optional(PrimitiveType(inner_value))))
    Ok(CollectionType(inner_value)) ->
      Ok(ModifierType(Optional(CollectionType(inner_value))))
    _ -> Error(Nil)
  }
}

fn parse_dict_type(inner_raw: String) -> Result(AcceptedTypes, Nil) {
  case
    inner_raw
    |> paren_innerds_split_and_trimmed
    |> list.map(parse_accepted_type)
  {
    [Ok(PrimitiveType(key_type)), Ok(PrimitiveType(value_type))] ->
      Ok(
        CollectionType(Dict(PrimitiveType(key_type), PrimitiveType(value_type))),
      )
    _ -> Error(Nil)
  }
}

fn parse_defaulted_type_two(raw: String) -> Result(AcceptedTypes, Nil) {
  use #(raw_inner_type, raw_default_value) <- result.try(
    case paren_innerds_split_and_trimmed(raw) {
      [typ, val] -> Ok(#(typ, val))
      _ -> Error(Nil)
    },
  )

  use parsed_inner_type <- result.try(parse_accepted_type(raw_inner_type))

  case validate_default_value(parsed_inner_type, raw_default_value) {
    Ok(_) -> Ok(ModifierType(Defaulted(parsed_inner_type, raw_default_value)))
    Error(_) -> Error(Nil)
  }
}

/// Validates a default value is compatible with the type (primitives only).
fn validate_default_value(
  typ: AcceptedTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  case typ {
    PrimitiveType(primitive) ->
      case primitive {
        Boolean if default_val == "True" || default_val == "False" -> Ok(Nil)
        Integer -> int.parse(default_val) |> result.replace(Nil)
        Float -> float.parse(default_val) |> result.replace(Nil)
        String -> Ok(Nil)
        _ -> Error(Nil)
      }
    // Defaulted only allows primitive types
    CollectionType(_) -> Error(Nil)
    ModifierType(_) -> Error(Nil)
  }
}

fn paren_innerds_trimmed(raw: String) -> String {
  raw
  |> string.replace("(", "")
  |> string.replace(")", "")
  |> string.trim
}

fn paren_innerds_split_and_trimmed(raw: String) -> List(String) {
  raw
  |> paren_innerds_trimmed
  |> string.split(",")
  |> list.map(string.trim)
}
