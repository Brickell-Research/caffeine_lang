import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string

/// Represents collection types that can contain accepted type values.
pub type CollectionTypes(accepted) {
  Dict(accepted, accepted)
  List(accepted)
}

/// Converts a CollectionTypes to its string representation.
@internal
pub fn collection_type_to_string(
  collection_type: CollectionTypes(accepted),
  accepted_type_to_string: fn(accepted) -> String,
) -> String {
  case collection_type {
    Dict(key_type, value_type) ->
      "Dict("
      <> accepted_type_to_string(key_type)
      <> ", "
      <> accepted_type_to_string(value_type)
      <> ")"
    List(inner_type) -> "List(" <> accepted_type_to_string(inner_type) <> ")"
  }
}

/// Parses a string into a CollectionTypes.
/// Returns the parsed collection type with its inner types parsed using the provided function.
@internal
pub fn parse_collection_type(
  raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
) -> Result(CollectionTypes(accepted), Nil) {
  case raw {
    "List" <> inside -> parse_list_type(inside, parse_inner)
    "Dict" <> inside -> parse_dict_type(inside, parse_inner)
    _ -> Error(Nil)
  }
}

fn parse_list_type(
  inner_raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
) -> Result(CollectionTypes(accepted), Nil) {
  case
    inner_raw
    |> paren_innerds_trimmed
    |> parse_inner
  {
    Ok(inner_type) -> Ok(List(inner_type))
    _ -> Error(Nil)
  }
}

fn parse_dict_type(
  inner_raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
) -> Result(CollectionTypes(accepted), Nil) {
  case
    inner_raw
    |> paren_innerds_split_and_trimmed
    |> list.map(parse_inner)
  {
    [Ok(key_type), Ok(value_type)] -> Ok(Dict(key_type, value_type))
    _ -> Error(Nil)
  }
}

/// Decoder for collection types - collections cannot be decoded to a single string.
@internal
pub fn decode_collection_to_string(
  _collection: CollectionTypes(accepted),
  _decode_inner: fn(accepted) -> decode.Decoder(String),
) -> decode.Decoder(String) {
  // Collections can't be converted to a single string value.
  decode.failure("", "Collection")
}

/// Validates a dynamic value matches the collection type.
/// Returns the original value if valid, or an error with decode errors.
@internal
pub fn validate_value(
  collection: CollectionTypes(accepted),
  value: Dynamic,
  validate_inner: fn(accepted, Dynamic) -> Result(Dynamic, List(decode.DecodeError)),
) -> Result(Dynamic, List(decode.DecodeError)) {
  case collection {
    Dict(_key_type, value_type) -> {
      case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
        Ok(dict_val) -> {
          dict_val
          |> dict.values
          |> list.try_map(fn(v) { validate_inner(value_type, v) })
          |> result.map(fn(_) { value })
        }
        Error(err) -> Error(err)
      }
    }
    List(inner_type) -> {
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(list_val) -> {
          list_val
          |> list.try_map(fn(v) { validate_inner(inner_type, v) })
          |> result.map(fn(_) { value })
        }
        Error(err) -> Error(err)
      }
    }
  }
}

/// Resolves a collection value to a string using the provided resolver functions.
/// Returns Error for Dict (unsupported), Ok with resolved string for List.
@internal
pub fn resolve_to_string(
  collection: CollectionTypes(accepted),
  value: Dynamic,
  decode_inner_to_string: fn(accepted) -> decode.Decoder(String),
  resolve_list: fn(List(String)) -> String,
  type_to_string: fn(CollectionTypes(accepted)) -> String,
) -> Result(String, String) {
  case collection {
    Dict(_, _) ->
      Error(
        "Unsupported templatized variable type: "
        <> type_to_string(collection)
        <> ". Dict support is pending, open an issue if this is a desired use case.",
      )
    List(inner_type) -> {
      let assert Ok(vals) =
        decode.run(value, decode.list(decode_inner_to_string(inner_type)))
      Ok(resolve_list(vals))
    }
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
