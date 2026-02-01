import caffeine_lang/common/collection_types.{type CollectionTypes}
import caffeine_lang/common/modifier_types.{
  type ModifierTypes, Defaulted, Optional,
}
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types.{type PrimitiveTypes}
import caffeine_lang/common/refinement_types.{type RefinementTypes, OneOf}
import caffeine_lang/common/type_info.{type TypeMeta}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string

/// AcceptedTypes is a union of all the types that can be used as a "filter" over the set
/// of all possible values. This allows us to _type_ params and thus provide annotations
/// that the compiler can leverage to be a more useful guide towards the pit of success.
pub type AcceptedTypes {
  PrimitiveType(PrimitiveTypes)
  CollectionType(CollectionTypes(AcceptedTypes))
  ModifierType(ModifierTypes(AcceptedTypes))
  RefinementType(RefinementTypes(AcceptedTypes))
  /// A reference to a type alias (e.g., _env). Must be resolved before validation.
  /// This is a compile-time construct that gets inlined during code generation.
  TypeAliasRef(String)
}

/// Converts an AcceptedTypes to its string representation.
@internal
pub fn accepted_type_to_string(accepted_type: AcceptedTypes) -> String {
  case accepted_type {
    PrimitiveType(primitive_type) ->
      primitive_types.primitive_type_to_string(primitive_type)
    CollectionType(collection_type) ->
      collection_types.collection_type_to_string(
        collection_type,
        accepted_type_to_string,
      )
    ModifierType(modifier_type) ->
      modifier_types.modifier_type_to_string(
        modifier_type,
        accepted_type_to_string,
      )
    RefinementType(refinement_type) ->
      refinement_types.refinement_type_to_string(
        refinement_type,
        accepted_type_to_string,
      )
    TypeAliasRef(name) ->
      // Type alias refs should be resolved before serialization.
      // If we hit this, the alias wasn't resolved - return the name for debugging.
      name
  }
}

/// Validates a dynamic value matches the expected AcceptedType.
/// Returns the original value if valid, or an error with decode errors.
@internal
pub fn validate_value(
  accepted_type: AcceptedTypes,
  value: Dynamic,
) -> Result(Dynamic, List(decode.DecodeError)) {
  case accepted_type {
    PrimitiveType(primitive) -> primitive_types.validate_value(primitive, value)
    CollectionType(collection) ->
      collection_types.validate_value(collection, value, validate_value)
    ModifierType(modifier) ->
      modifier_types.validate_value(modifier, value, validate_value)
    RefinementType(refinement) ->
      refinement_types.validate_value(
        refinement,
        value,
        decode_value_to_string,
        get_numeric_type,
      )
    TypeAliasRef(name) ->
      // Type alias refs must be resolved before validation
      Error([decode.DecodeError("Unresolved type alias: " <> name, "Type", [])])
  }
}

/// Decoder that converts a dynamic value to its String representation based on type.
/// Dispatches to type-specific decoders.
@internal
pub fn decode_value_to_string(typ: AcceptedTypes) -> decode.Decoder(String) {
  case typ {
    PrimitiveType(primitive) ->
      primitive_types.decode_primitive_to_string(primitive)
    CollectionType(collection) ->
      collection_types.decode_collection_to_string(
        collection,
        decode_value_to_string,
      )
    ModifierType(modifier) ->
      modifier_types.decode_modifier_to_string(modifier, decode_value_to_string)
    RefinementType(refinement) ->
      refinement_types.decode_refinement_to_string(
        refinement,
        decode_value_to_string,
      )
    TypeAliasRef(name) ->
      // Type alias refs must be resolved before decoding
      decode.failure("Unresolved type alias: " <> name, "Type")
  }
}

/// Decoder that converts a list of dynamic values to List(String).
@internal
pub fn decode_list_values_to_strings(
  inner_type: AcceptedTypes,
) -> decode.Decoder(List(String)) {
  decode.list(decode_value_to_string(inner_type))
}

/// Parses a string into an AcceptedTypes.
@internal
pub fn parse_accepted_type(raw: String) -> Result(AcceptedTypes, Nil) {
  primitive_types.parse_primitive_type(raw)
  |> result.map(PrimitiveType)
  |> result.lazy_or(fn() {
    collection_types.parse_collection_type(raw, parse_primitive_or_collection)
    |> result.map(CollectionType)
  })
  |> result.lazy_or(fn() {
    modifier_types.parse_modifier_type(
      raw,
      parse_primitive_or_collection,
      validate_string_literal,
    )
    |> result.map(ModifierType)
  })
  |> result.lazy_or(fn() {
    refinement_types.parse_refinement_type(
      raw,
      parse_primitive_or_defaulted,
      validate_string_literal_or_defaulted,
    )
    |> result.map(RefinementType)
  })
  |> result.lazy_or(fn() { parse_type_alias_ref(raw) })
}

/// Resolves a value to a string using the provided resolver functions.
/// Dispatches to type-specific resolution logic.
@internal
pub fn resolve_to_string(
  typ: AcceptedTypes,
  value: Dynamic,
  resolve_string: fn(String) -> String,
  resolve_list: fn(List(String)) -> String,
) -> Result(String, String) {
  case typ {
    PrimitiveType(primitive) ->
      Ok(primitive_types.resolve_to_string(primitive, value, resolve_string))
    CollectionType(collection) ->
      collection_types.resolve_to_string(
        collection,
        value,
        decode_value_to_string,
        resolve_list,
        collection_type_to_string,
      )
    ModifierType(modifier) ->
      modifier_types.resolve_to_string(
        modifier,
        value,
        fn(inner_typ, inner_val) {
          resolve_to_string(inner_typ, inner_val, resolve_string, resolve_list)
        },
        resolve_string,
      )
    RefinementType(refinement) ->
      refinement_types.resolve_to_string(
        refinement,
        value,
        decode_value_to_string,
        resolve_string,
      )
    TypeAliasRef(name) ->
      // Type alias refs must be resolved before resolution
      Error("Unresolved type alias: " <> name)
  }
}

/// Extracts the NumericTypes from an AcceptedTypes.
/// Used by InclusiveRange validation - only Integer/Float primitives are valid.
///
/// INVARIANT: This function should only be called with types that are known to be
/// numeric (Integer or Float). The caller is responsible for ensuring this.
/// If a non-numeric type is passed, this returns Integer as a fallback but the
/// validation will likely fail with a type mismatch error upstream.
///
/// TypeAliasRef should never reach this function - they must be resolved before
/// validation. If one does, it indicates a bug in the resolution pipeline.
@internal
pub fn get_numeric_type(typ: AcceptedTypes) -> numeric_types.NumericTypes {
  case typ {
    PrimitiveType(primitive_types.NumericType(numeric)) -> numeric
    // TypeAliasRef should be resolved before reaching validation
    // If we get here, there's a bug - but we fall through to avoid crashing
    TypeAliasRef(_) -> numeric_types.Integer
    // InclusiveRange only allows Integer/Float, so these shouldn't happen
    // Fallback to Integer - upstream validation will catch the mismatch
    PrimitiveType(primitive_types.SemanticType(_)) -> numeric_types.Integer
    PrimitiveType(primitive_types.String) -> numeric_types.Integer
    PrimitiveType(primitive_types.Boolean) -> numeric_types.Integer
    CollectionType(_) -> numeric_types.Integer
    ModifierType(_) -> numeric_types.Integer
    RefinementType(_) -> numeric_types.Integer
  }
}

/// Parser for primitives, collections (recursively nested), refinements, or type alias refs.
/// Used as the inner parser for both collection and modifier type parsing.
fn parse_primitive_or_collection(raw: String) -> Result(AcceptedTypes, Nil) {
  primitive_types.parse_primitive_type(raw)
  |> result.map(PrimitiveType)
  |> result.lazy_or(fn() {
    collection_types.parse_collection_type(raw, parse_primitive_or_collection)
    |> result.map(CollectionType)
  })
  |> result.lazy_or(fn() {
    refinement_types.parse_refinement_type(
      raw,
      parse_primitive_or_defaulted,
      validate_string_literal_or_defaulted,
    )
    |> result.map(RefinementType)
  })
  |> result.lazy_or(fn() { parse_type_alias_ref(raw) })
}

/// Parser for primitives or Defaulted modifiers - used for refinement type inner types.
/// Only allows Integer, Float, String (not Boolean) or Defaulted with those types.
fn parse_primitive_or_defaulted(raw: String) -> Result(AcceptedTypes, Nil) {
  primitive_types.parse_refinement_compatible_primitive(raw)
  |> result.map(PrimitiveType)
  |> result.lazy_or(fn() {
    modifier_types.parse_modifier_type(
      raw,
      fn(inner) {
        primitive_types.parse_refinement_compatible_primitive(inner)
        |> result.map(PrimitiveType)
      },
      validate_string_literal,
    )
    |> result.map(ModifierType)
  })
}

// Validates a string literal value is valid for a type.
// Used for default values in modifiers and set values in refinement types.
fn validate_string_literal(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    PrimitiveType(primitive) ->
      primitive_types.validate_default_value(primitive, value)
    RefinementType(refinement) ->
      refinement_types.validate_default_value(
        refinement,
        value,
        validate_string_literal,
        get_numeric_type,
      )
    ModifierType(modifier) ->
      modifier_types.validate_default_value_recursive(
        modifier,
        value,
        validate_string_literal,
      )
    CollectionType(_) -> Error(Nil)
    TypeAliasRef(_) -> Error(Nil)
  }
}

// Validates a string literal for refinement types - supports primitives and Defaulted.
fn validate_string_literal_or_defaulted(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    PrimitiveType(primitive) ->
      primitive_types.validate_default_value(primitive, value)
    ModifierType(modifier) ->
      modifier_types.validate_default_value_recursive(
        modifier,
        value,
        validate_string_literal_or_defaulted,
      )
    _ -> Error(Nil)
  }
}

/// Checks if a type is optional or has a default value.
/// Recurses through OneOf refinement types to check the inner type.
@internal
pub fn is_optional_or_defaulted(typ: AcceptedTypes) -> Bool {
  case typ {
    ModifierType(Optional(_)) -> True
    ModifierType(Defaulted(_, _)) -> True
    RefinementType(OneOf(inner, _)) -> is_optional_or_defaulted(inner)
    _ -> False
  }
}

/// Returns all type metadata across all type categories.
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  list.flatten([
    primitive_types.all_type_metas(),
    collection_types.all_type_metas(),
    modifier_types.all_type_metas(),
    refinement_types.all_type_metas(),
  ])
}

/// Applies a fallible check to each inner type in a compound type.
/// For leaf types (PrimitiveType, TypeAliasRef), calls the function directly.
/// For compound types (Collection, Modifier, Refinement), extracts inner types and applies the function.
@internal
pub fn try_each_inner(
  typ: AcceptedTypes,
  f: fn(AcceptedTypes) -> Result(Nil, e),
) -> Result(Nil, e) {
  case typ {
    PrimitiveType(_) -> f(typ)
    TypeAliasRef(_) -> f(typ)
    CollectionType(collection) -> collection_types.try_each_inner(collection, f)
    ModifierType(modifier) -> modifier_types.try_each_inner(modifier, f)
    RefinementType(refinement) -> refinement_types.try_each_inner(refinement, f)
  }
}

/// Transforms each inner type in a compound type using a mapping function.
/// For leaf types (PrimitiveType, TypeAliasRef), calls the function directly.
/// For compound types (Collection, Modifier, Refinement), extracts inner types,
/// applies the function, and reconstructs the compound type.
@internal
pub fn map_inner(
  typ: AcceptedTypes,
  f: fn(AcceptedTypes) -> AcceptedTypes,
) -> AcceptedTypes {
  case typ {
    PrimitiveType(_) -> f(typ)
    TypeAliasRef(_) -> f(typ)
    CollectionType(collection) ->
      CollectionType(collection_types.map_inner(collection, f))
    ModifierType(modifier) ->
      ModifierType(modifier_types.map_inner(modifier, f))
    RefinementType(refinement) ->
      RefinementType(refinement_types.map_inner(refinement, f))
  }
}

/// Parses a type alias reference (must start with _ and have more characters).
fn parse_type_alias_ref(raw: String) -> Result(AcceptedTypes, Nil) {
  case string.starts_with(raw, "_") && string.length(raw) > 1 {
    True -> Ok(TypeAliasRef(raw))
    False -> Error(Nil)
  }
}

/// Converts a CollectionTypes to its string representation.
fn collection_type_to_string(
  collection: CollectionTypes(AcceptedTypes),
) -> String {
  collection_types.collection_type_to_string(
    collection,
    accepted_type_to_string,
  )
}
