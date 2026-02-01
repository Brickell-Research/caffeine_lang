import caffeine_lang/common/parsing_utils
import caffeine_lang/common/type_info.{type TypeMeta, TypeMeta}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result

/// Represents collection types that can contain accepted type values.
pub type CollectionTypes(accepted) {
  Dict(accepted, accepted)
  List(accepted)
}

/// Returns metadata for all CollectionTypes variants.
/// IMPORTANT: Update this when adding new variants!
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  [collection_type_meta(List(Nil)), collection_type_meta(Dict(Nil, Nil))]
}

/// Returns metadata for a CollectionTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
fn collection_type_meta(typ: CollectionTypes(accepted)) -> TypeMeta {
  case typ {
    List(_) ->
      TypeMeta(
        name: "List",
        description: "An ordered sequence where each element shares the same type",
        syntax: "List(T)",
        example: "List(String), List(Integer)",
      )
    Dict(_, _) ->
      TypeMeta(
        name: "Dict",
        description: "A key-value map with typed keys and values",
        syntax: "Dict(K, V)",
        example: "Dict(String, String), Dict(String, Integer)",
      )
  }
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
    |> parsing_utils.paren_innerds_trimmed
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
    |> parsing_utils.paren_innerds_split_and_trimmed
    |> list.map(parse_inner)
  {
    [Ok(key_type), Ok(value_type)] -> Ok(Dict(key_type, value_type))
    _ -> Error(Nil)
  }
}

/// Applies a fallible check to each inner type in a collection type.
@internal
pub fn try_each_inner(
  collection: CollectionTypes(accepted),
  f: fn(accepted) -> Result(Nil, e),
) -> Result(Nil, e) {
  case collection {
    List(inner) -> f(inner)
    Dict(key, value) -> {
      use _ <- result.try(f(key))
      f(value)
    }
  }
}

/// Transforms each inner type in a collection type using a mapping function.
@internal
pub fn map_inner(
  collection: CollectionTypes(accepted),
  f: fn(accepted) -> accepted,
) -> CollectionTypes(accepted) {
  case collection {
    List(inner) -> List(f(inner))
    Dict(key, value) -> Dict(f(key), f(value))
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
/// For Dict types, validates both keys and values against their respective types.
@internal
pub fn validate_value(
  collection: CollectionTypes(accepted),
  value: Dynamic,
  validate_inner: fn(accepted, Dynamic) ->
    Result(Dynamic, List(decode.DecodeError)),
) -> Result(Dynamic, List(decode.DecodeError)) {
  case collection {
    Dict(key_type, value_type) -> {
      case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
        Ok(dict_val) -> {
          dict_val
          |> dict.to_list
          |> list.try_map(fn(pair) {
            let #(k, v) = pair
            // Validate key - convert string key to dynamic for validation
            use _ <- result.try(
              validate_inner(key_type, dynamic.string(k))
              |> result.map_error(fn(errs) {
                list.map(errs, fn(e) {
                  decode.DecodeError(..e, path: [k, ..e.path])
                })
              }),
            )
            // Validate value
            validate_inner(value_type, v)
            |> result.map_error(fn(errs) {
              list.map(errs, fn(e) {
                decode.DecodeError(..e, path: [k, ..e.path])
              })
            })
          })
          |> result.map(fn(_) { value })
        }
        Error(err) -> Error(err)
      }
    }
    List(inner_type) -> {
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(list_val) -> {
          list_val
          |> list.index_map(fn(v, i) { #(v, i) })
          |> list.try_map(fn(pair) {
            let #(v, i) = pair
            validate_inner(inner_type, v)
            |> result.map_error(fn(errs) {
              list.map(errs, fn(e) {
                decode.DecodeError(..e, path: [int.to_string(i), ..e.path])
              })
            })
          })
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
      use vals <- result.try(
        decode.run(value, decode.list(decode_inner_to_string(inner_type)))
        |> result.map_error(fn(_) {
          "Failed to decode list values for type: "
          <> type_to_string(collection)
        }),
      )
      Ok(resolve_list(vals))
    }
  }
}
