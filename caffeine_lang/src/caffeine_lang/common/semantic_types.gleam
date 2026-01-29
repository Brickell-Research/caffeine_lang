import caffeine_lang/common/type_info.{type TypeMeta, TypeMeta}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/string

/// SemanticStringTypes are strings with semantic meaning and validation.
pub type SemanticStringTypes {
  URL
}

/// Returns metadata for all SemanticStringTypes variants.
/// IMPORTANT: Update this when adding new variants!
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  [semantic_type_meta(URL)]
}

/// Returns metadata for a SemanticStringTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
@internal
pub fn semantic_type_meta(typ: SemanticStringTypes) -> TypeMeta {
  case typ {
    URL ->
      TypeMeta(
        name: "URL",
        description: "A valid URL starting with http:// or https://",
        syntax: "URL",
        example: "\"https://example.com\"",
      )
  }
}

/// Converts a SemanticStringTypes to its string representation.
pub fn semantic_type_to_string(typ: SemanticStringTypes) -> String {
  case typ {
    URL -> "URL"
  }
}

/// Parses a string into a SemanticStringTypes.
@internal
pub fn parse_semantic_type(raw: String) -> Result(SemanticStringTypes, Nil) {
  case raw {
    "URL" -> Ok(URL)
    _ -> Error(Nil)
  }
}

/// Decoder that converts a dynamic semantic string value to its String representation.
@internal
pub fn decode_semantic_to_string(
  _typ: SemanticStringTypes,
) -> decode.Decoder(String) {
  decode.string
}

/// Validates a default value is compatible with the semantic string type.
@internal
pub fn validate_default_value(
  typ: SemanticStringTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  case typ {
    URL -> validate_url(default_val)
  }
}

/// Validates a dynamic value matches the semantic string type.
@internal
pub fn validate_value(
  typ: SemanticStringTypes,
  value: Dynamic,
) -> Result(Dynamic, List(decode.DecodeError)) {
  let decoder = {
    use str <- decode.then(decode.string)
    case typ {
      URL ->
        case validate_url(str) {
          Ok(Nil) -> decode.success(value)
          Error(Nil) ->
            decode.failure(value, "URL (starting with http:// or https://)")
        }
    }
  }
  decode.run(value, decoder)
}

fn validate_url(val: String) -> Result(Nil, Nil) {
  case
    string.starts_with(val, "http://") || string.starts_with(val, "https://")
  {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}
