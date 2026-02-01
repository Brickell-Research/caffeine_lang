import caffeine_lang/common/numeric_types.{type NumericTypes}
import caffeine_lang/common/semantic_types.{type SemanticStringTypes}
import caffeine_lang/common/type_info.{type TypeMeta, TypeMeta}
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result

/// Parses only refinement-compatible primitives: String, Integer, Float.
/// Excludes Boolean and semantic types which are not valid in refinement contexts.
@internal
pub fn parse_refinement_compatible_primitive(
  raw: String,
) -> Result(PrimitiveTypes, Nil) {
  case raw {
    "String" -> Ok(String)
    _ ->
      numeric_types.parse_numeric_type(raw)
      |> result.map(NumericType)
  }
}

/// PrimitiveTypes are the most _atomic_ of types. I.E. the simple ones
/// most folks think of: Boolean, Float, Integer, String.
pub type PrimitiveTypes {
  Boolean
  String
  NumericType(NumericTypes)
  SemanticType(SemanticStringTypes)
}

/// Returns metadata for all PrimitiveTypes variants.
/// IMPORTANT: Update this when adding new variants!
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  list.flatten([
    [primitive_type_meta(Boolean), primitive_type_meta(String)],
    numeric_types.all_type_metas(),
    semantic_types.all_type_metas(),
  ])
}

/// Returns metadata for a PrimitiveTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
fn primitive_type_meta(typ: PrimitiveTypes) -> TypeMeta {
  case typ {
    Boolean ->
      TypeMeta(
        name: "Boolean",
        description: "True or false",
        syntax: "Boolean",
        example: "true, false",
      )
    String ->
      TypeMeta(
        name: "String",
        description: "Any text between double quotes",
        syntax: "String",
        example: "\"hello\", \"my-service\"",
      )
    NumericType(n) -> numeric_types.numeric_type_meta(n)
    SemanticType(s) -> semantic_types.semantic_type_meta(s)
  }
}

/// Converts a PrimitiveTypes to its string representation.
@internal
pub fn primitive_type_to_string(primitive_type: PrimitiveTypes) -> String {
  case primitive_type {
    Boolean -> "Boolean"
    String -> "String"
    NumericType(numeric_type) ->
      numeric_types.numeric_type_to_string(numeric_type)
    SemanticType(semantic_type) ->
      semantic_types.semantic_type_to_string(semantic_type)
  }
}

/// Parses a string into a PrimitiveTypes.
@internal
pub fn parse_primitive_type(raw: String) -> Result(PrimitiveTypes, Nil) {
  case raw {
    "Boolean" -> Ok(Boolean)
    "String" -> Ok(String)
    _ ->
      numeric_types.parse_numeric_type(raw)
      |> result.map(NumericType)
      |> result.lazy_or(fn() {
        semantic_types.parse_semantic_type(raw)
        |> result.map(SemanticType)
      })
  }
}

/// Decoder that converts a dynamic primitive value to its String representation.
@internal
pub fn decode_primitive_to_string(
  primitive: PrimitiveTypes,
) -> decode.Decoder(String) {
  case primitive {
    Boolean -> {
      use val <- decode.then(decode.bool)
      decode.success(bool.to_string(val))
    }
    String -> decode.string
    NumericType(numeric_type) ->
      numeric_types.decode_numeric_to_string(numeric_type)
    SemanticType(semantic_type) ->
      semantic_types.decode_semantic_to_string(semantic_type)
  }
}

/// Validates a default value is compatible with the primitive type.
@internal
pub fn validate_default_value(
  primitive: PrimitiveTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  case primitive {
    Boolean if default_val == "True" || default_val == "False" -> Ok(Nil)
    Boolean -> Error(Nil)
    String -> Ok(Nil)
    NumericType(numeric_type) ->
      numeric_types.validate_default_value(numeric_type, default_val)
    SemanticType(semantic_type) ->
      semantic_types.validate_default_value(semantic_type, default_val)
  }
}

/// Validates a dynamic value matches the primitive type.
@internal
pub fn validate_value(
  primitive: PrimitiveTypes,
  value: Dynamic,
) -> Result(Dynamic, List(decode.DecodeError)) {
  case primitive {
    Boolean -> {
      let decoder = decode.bool |> decode.map(fn(_) { value })
      decode.run(value, decoder)
    }
    String -> {
      let decoder = decode.string |> decode.map(fn(_) { value })
      decode.run(value, decoder)
    }
    NumericType(numeric_type) ->
      numeric_types.validate_value(numeric_type, value)
    SemanticType(semantic_type) ->
      semantic_types.validate_value(semantic_type, value)
  }
}

/// Resolves a primitive value to a string using the provided resolver function.
/// Decodes the value and applies the resolver to produce the final string.
@internal
pub fn resolve_to_string(
  primitive: PrimitiveTypes,
  value: Dynamic,
  resolve_string: fn(String) -> String,
) -> String {
  let assert Ok(val) = decode.run(value, decode_primitive_to_string(primitive))
  resolve_string(val)
}
