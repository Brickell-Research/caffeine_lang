import caffeine_lang/parsing_utils
import caffeine_lang/value.{type Value}
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string

// ---------------------------------------------------------------------------
// Type definitions
// ---------------------------------------------------------------------------

/// AcceptedTypes is a union of all the types that can be used as a "filter" over the set
/// of all possible values. This allows us to _type_ params and thus provide annotations
/// that the compiler can leverage to be a more useful guide towards the pit of success.
pub type AcceptedTypes {
  PrimitiveType(PrimitiveTypes)
  CollectionType(CollectionTypes(AcceptedTypes))
  ModifierType(ModifierTypes(AcceptedTypes))
  RefinementType(RefinementTypes(AcceptedTypes))
}

/// ParsedType is the frontend counterpart of AcceptedTypes that allows type alias
/// references. It exists only in the parser → validator → formatter → lowering pipeline.
/// After lowering resolves all aliases, downstream code works with pure AcceptedTypes.
pub type ParsedType {
  ParsedPrimitive(PrimitiveTypes)
  ParsedCollection(CollectionTypes(ParsedType))
  ParsedModifier(ModifierTypes(ParsedType))
  ParsedRefinement(RefinementTypes(ParsedType))
  /// A reference to a type alias (e.g., _env). Resolved during lowering.
  ParsedTypeAliasRef(String)
}

/// PrimitiveTypes are the most _atomic_ of types. I.E. the simple ones
/// most folks think of: Boolean, Float, Integer, String.
pub type PrimitiveTypes {
  Boolean
  String
  NumericType(NumericTypes)
  SemanticType(SemanticStringTypes)
}

/// NumericTypes are just _numbers_ which have a variety of representations.
pub type NumericTypes {
  Float
  Integer
}

/// SemanticStringTypes are strings with semantic meaning and validation.
pub type SemanticStringTypes {
  URL
}

/// Represents collection types that can contain accepted type values.
pub type CollectionTypes(accepted) {
  Dict(accepted, accepted)
  List(accepted)
}

/// Modifier types are a special class of types that alter the value semantics of
/// the attribute they are bound to.
pub type ModifierTypes(accepted) {
  Optional(accepted)
  /// Defaulted type stores the inner type and its default value as a string
  /// e.g., Defaulted(Integer, "10") means an optional integer with default 10
  Defaulted(accepted, String)
}

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

/// Validation error with expected type, found value, and path context.
/// Replaces decode.DecodeError to eliminate the gleam/dynamic/decode dependency.
pub type ValidationError {
  ValidationError(expected: String, found: String, path: List(String))
}

/// Type metadata for display purposes.
pub type TypeMeta {
  TypeMeta(name: String, description: String, syntax: String, example: String)
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

/// Returns all type metadata across all type categories.
/// Includes refinement types (OneOf, InclusiveRange) which are not standalone
/// types but are useful for documentation (hover, CLI `types` command).
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  list.flatten([completable_type_metas(), refinement_all_type_metas()])
}

/// Returns type metadata for types that can be used directly in type position.
/// Excludes refinement types (OneOf, InclusiveRange) since those are syntactic
/// modifiers applied to other types (e.g. `String { x | x in { a, b } }`),
/// not standalone type names a user would type.
@internal
pub fn completable_type_metas() -> List(TypeMeta) {
  list.flatten([
    primitive_all_type_metas(),
    collection_all_type_metas(),
    modifier_all_type_metas(),
  ])
}

fn primitive_all_type_metas() -> List(TypeMeta) {
  list.flatten([
    [primitive_type_meta(Boolean), primitive_type_meta(String)],
    numeric_all_type_metas(),
    semantic_all_type_metas(),
  ])
}

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
    NumericType(n) -> numeric_type_meta(n)
    SemanticType(s) -> semantic_type_meta(s)
  }
}

fn numeric_all_type_metas() -> List(TypeMeta) {
  [numeric_type_meta(Integer), numeric_type_meta(Float)]
}

/// Returns metadata for a NumericTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
@internal
pub fn numeric_type_meta(typ: NumericTypes) -> TypeMeta {
  case typ {
    Integer ->
      TypeMeta(
        name: "Integer",
        description: "Whole numbers",
        syntax: "Integer",
        example: "42, 0, -10",
      )
    Float ->
      TypeMeta(
        name: "Float",
        description: "Decimal numbers",
        syntax: "Float",
        example: "3.14, 99.9, 0.0",
      )
  }
}

fn semantic_all_type_metas() -> List(TypeMeta) {
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

fn collection_all_type_metas() -> List(TypeMeta) {
  [collection_type_meta(List(Nil)), collection_type_meta(Dict(Nil, Nil))]
}

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

fn modifier_all_type_metas() -> List(TypeMeta) {
  [modifier_type_meta(Optional(Nil)), modifier_type_meta(Defaulted(Nil, ""))]
}

fn modifier_type_meta(typ: ModifierTypes(accepted)) -> TypeMeta {
  case typ {
    Optional(_) ->
      TypeMeta(
        name: "Optional",
        description: "A type where the value may be left unspecified",
        syntax: "Optional(T)",
        example: "Optional(String), Optional(Integer)",
      )
    Defaulted(_, _) ->
      TypeMeta(
        name: "Defaulted",
        description: "A type with a default value if none is provided",
        syntax: "Defaulted(T, default)",
        example: "Defaulted(Integer, 30), Defaulted(String, \"prod\")",
      )
  }
}

fn refinement_all_type_metas() -> List(TypeMeta) {
  [
    refinement_type_meta(OneOf(Nil, set.new())),
    refinement_type_meta(InclusiveRange(Nil, "", "")),
  ]
}

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

// ---------------------------------------------------------------------------
// To-string operations
// ---------------------------------------------------------------------------

/// Converts an AcceptedTypes to its string representation.
@internal
pub fn accepted_type_to_string(accepted_type: AcceptedTypes) -> String {
  case accepted_type {
    PrimitiveType(primitive_type) -> primitive_type_to_string(primitive_type)
    CollectionType(collection_type) ->
      collection_type_to_string(collection_type)
    ModifierType(modifier_type) -> modifier_type_to_string(modifier_type)
    RefinementType(refinement_type) ->
      refinement_type_to_string(refinement_type)
  }
}

/// Converts a PrimitiveTypes to its string representation.
@internal
pub fn primitive_type_to_string(primitive_type: PrimitiveTypes) -> String {
  case primitive_type {
    Boolean -> "Boolean"
    String -> "String"
    NumericType(numeric_type) -> numeric_type_to_string(numeric_type)
    SemanticType(semantic_type) -> semantic_type_to_string(semantic_type)
  }
}

/// Converts a NumericTypes to its string representation.
pub fn numeric_type_to_string(numeric_type: NumericTypes) -> String {
  case numeric_type {
    Float -> "Float"
    Integer -> "Integer"
  }
}

/// Converts a SemanticStringTypes to its string representation.
pub fn semantic_type_to_string(typ: SemanticStringTypes) -> String {
  case typ {
    URL -> "URL"
  }
}

/// Converts a CollectionTypes to its string representation.
@internal
pub fn collection_type_to_string(
  collection_type: CollectionTypes(AcceptedTypes),
) -> String {
  collection_to_string(collection_type, accepted_type_to_string)
}

/// Converts a ModifierTypes to its string representation.
@internal
pub fn modifier_type_to_string(
  modifier_type: ModifierTypes(AcceptedTypes),
) -> String {
  modifier_to_string(modifier_type, accepted_type_to_string)
}

/// Converts a RefinementTypes to its string representation.
@internal
pub fn refinement_type_to_string(
  refinement: RefinementTypes(AcceptedTypes),
) -> String {
  refinement_to_string(refinement, accepted_type_to_string)
}

/// Generic collection-to-string using a recursive formatter.
fn collection_to_string(
  collection_type: CollectionTypes(a),
  to_string: fn(a) -> String,
) -> String {
  case collection_type {
    Dict(key_type, value_type) ->
      "Dict(" <> to_string(key_type) <> ", " <> to_string(value_type) <> ")"
    List(inner_type) -> "List(" <> to_string(inner_type) <> ")"
  }
}

/// Generic modifier-to-string using a recursive formatter.
fn modifier_to_string(
  modifier_type: ModifierTypes(a),
  to_string: fn(a) -> String,
) -> String {
  case modifier_type {
    Optional(inner_type) -> "Optional(" <> to_string(inner_type) <> ")"
    Defaulted(inner_type, default_val) ->
      "Defaulted(" <> to_string(inner_type) <> ", " <> default_val <> ")"
  }
}

/// Generic refinement-to-string using a recursive formatter.
fn refinement_to_string(
  refinement: RefinementTypes(a),
  to_string: fn(a) -> String,
) -> String {
  case refinement {
    OneOf(typ, set_vals) ->
      to_string(typ)
      <> " { x | x in { "
      <> set_vals
      |> set.to_list
      |> list.sort(string.compare)
      |> string.join(", ")
      <> " } }"
    InclusiveRange(typ, low, high) ->
      to_string(typ) <> " { x | x in ( " <> low <> ".." <> high <> " ) }"
  }
}

// ---------------------------------------------------------------------------
// ParsedType operations
// ---------------------------------------------------------------------------

/// Converts a ParsedType to its string representation.
@internal
pub fn parsed_type_to_string(parsed_type: ParsedType) -> String {
  case parsed_type {
    ParsedPrimitive(primitive_type) -> primitive_type_to_string(primitive_type)
    ParsedCollection(collection_type) ->
      collection_to_string(collection_type, parsed_type_to_string)
    ParsedModifier(modifier_type) ->
      modifier_to_string(modifier_type, parsed_type_to_string)
    ParsedRefinement(refinement_type) ->
      refinement_to_string(refinement_type, parsed_type_to_string)
    ParsedTypeAliasRef(name) -> name
  }
}

/// Applies a fallible check to each inner type in a parsed compound type.
@internal
pub fn try_each_inner_parsed(
  typ: ParsedType,
  f: fn(ParsedType) -> Result(Nil, e),
) -> Result(Nil, e) {
  case typ {
    ParsedPrimitive(_) -> f(typ)
    ParsedTypeAliasRef(_) -> f(typ)
    ParsedCollection(collection) -> collection_try_each_inner(collection, f)
    ParsedModifier(modifier) -> modifier_try_each_inner(modifier, f)
    ParsedRefinement(refinement) -> refinement_try_each_inner(refinement, f)
  }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Parses a string into an AcceptedTypes.
@internal
pub fn parse_accepted_type(raw: String) -> Result(AcceptedTypes, Nil) {
  parse_primitive_type(raw)
  |> result.map(PrimitiveType)
  |> result.lazy_or(fn() {
    parse_collection_type(raw, parse_primitive_or_collection)
    |> result.map(CollectionType)
  })
  |> result.lazy_or(fn() {
    parse_modifier_type(
      raw,
      parse_primitive_or_collection,
      validate_string_literal,
    )
    |> result.map(ModifierType)
  })
  |> result.lazy_or(fn() {
    parse_refinement_type(
      raw,
      parse_primitive_or_defaulted,
      validate_string_literal_or_defaulted,
    )
    |> result.map(RefinementType)
  })
}

/// Parses a string into a PrimitiveTypes.
@internal
pub fn parse_primitive_type(raw: String) -> Result(PrimitiveTypes, Nil) {
  case raw {
    "Boolean" -> Ok(Boolean)
    "String" -> Ok(String)
    _ ->
      parse_numeric_type(raw)
      |> result.map(NumericType)
      |> result.lazy_or(fn() {
        parse_semantic_type(raw)
        |> result.map(SemanticType)
      })
  }
}

/// Parses only refinement-compatible primitives: String, Integer, Float.
/// Excludes Boolean and semantic types which are not valid in refinement contexts.
@internal
pub fn parse_refinement_compatible_primitive(
  raw: String,
) -> Result(PrimitiveTypes, Nil) {
  case raw {
    "String" -> Ok(String)
    _ ->
      parse_numeric_type(raw)
      |> result.map(NumericType)
  }
}

/// Parses a string into a NumericTypes.
@internal
pub fn parse_numeric_type(raw: String) -> Result(NumericTypes, Nil) {
  case raw {
    "Float" -> Ok(Float)
    "Integer" -> Ok(Integer)
    _ -> Error(Nil)
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

/// Parses a string into a ModifierTypes.
@internal
pub fn parse_modifier_type(
  raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
  validate_default: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(ModifierTypes(accepted), Nil) {
  case raw {
    "Optional" <> rest -> parse_optional_type(rest, parse_inner)
    "Defaulted" <> rest ->
      parse_defaulted_type(rest, parse_inner, validate_default)
    _ -> Error(Nil)
  }
}

fn parse_optional_type(
  raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
) -> Result(ModifierTypes(accepted), Nil) {
  case
    raw
    |> parsing_utils.paren_innerds_trimmed
    |> parse_inner
  {
    Ok(inner_type) -> Ok(Optional(inner_type))
    _ -> Error(Nil)
  }
}

fn parse_defaulted_type(
  raw: String,
  parse_inner: fn(String) -> Result(accepted, Nil),
  validate_default: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(ModifierTypes(accepted), Nil) {
  use #(raw_inner_type, raw_default_value) <- result.try(
    case parsing_utils.paren_innerds_split_and_trimmed(raw) {
      [typ, val] -> Ok(#(typ, val))
      _ -> Error(Nil)
    },
  )

  use parsed_inner_type <- result.try(parse_inner(raw_inner_type))

  case validate_default(parsed_inner_type, raw_default_value) {
    Ok(_) -> Ok(Defaulted(parsed_inner_type, raw_default_value))
    Error(_) -> Error(Nil)
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
  case parse_numeric_type(raw_typ) {
    Ok(numeric) ->
      validate_in_range(numeric, low, low, high)
      |> result.replace_error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

/// Parser for primitives, collections (recursively nested), and refinements.
/// Used as the inner parser for both collection and modifier type parsing.
fn parse_primitive_or_collection(raw: String) -> Result(AcceptedTypes, Nil) {
  parse_primitive_type(raw)
  |> result.map(PrimitiveType)
  |> result.lazy_or(fn() {
    parse_collection_type(raw, parse_primitive_or_collection)
    |> result.map(CollectionType)
  })
  |> result.lazy_or(fn() {
    parse_refinement_type(
      raw,
      parse_primitive_or_defaulted,
      validate_string_literal_or_defaulted,
    )
    |> result.map(RefinementType)
  })
}

/// Parser for primitives or Defaulted modifiers - used for refinement type inner types.
/// Only allows Integer, Float, String (not Boolean) or Defaulted with those types.
fn parse_primitive_or_defaulted(raw: String) -> Result(AcceptedTypes, Nil) {
  parse_refinement_compatible_primitive(raw)
  |> result.map(PrimitiveType)
  |> result.lazy_or(fn() {
    parse_modifier_type(
      raw,
      fn(inner) {
        parse_refinement_compatible_primitive(inner)
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
      validate_primitive_default_value(primitive, value)
    RefinementType(refinement) ->
      validate_refinement_default_value(
        refinement,
        value,
        validate_string_literal,
      )
    ModifierType(modifier) ->
      validate_modifier_default_value_recursive(
        modifier,
        value,
        validate_string_literal,
      )
    CollectionType(_) -> Error(Nil)
  }
}

// Validates a string literal for refinement types - supports primitives and Defaulted.
fn validate_string_literal_or_defaulted(
  typ: AcceptedTypes,
  value: String,
) -> Result(Nil, Nil) {
  case typ {
    PrimitiveType(primitive) ->
      validate_primitive_default_value(primitive, value)
    ModifierType(modifier) ->
      validate_modifier_default_value_recursive(
        modifier,
        value,
        validate_string_literal_or_defaulted,
      )
    _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Validates a typed Value matches the expected AcceptedType.
/// Returns the original value if valid, or an error with decode errors.
@internal
pub fn validate_value(
  accepted_type: AcceptedTypes,
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case accepted_type {
    PrimitiveType(primitive) -> validate_primitive_value(primitive, val)
    CollectionType(collection) -> validate_collection_value(collection, val)
    ModifierType(modifier) -> validate_modifier_value(modifier, val)
    RefinementType(refinement) -> validate_refinement_value(refinement, val)
  }
}

fn validate_primitive_value(
  primitive: PrimitiveTypes,
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case primitive, val {
    Boolean, value.BoolValue(_) -> Ok(val)
    Boolean, _ ->
      Error([
        ValidationError(expected: "Bool", found: value.classify(val), path: []),
      ])
    String, value.StringValue(_) -> Ok(val)
    String, _ ->
      Error([
        ValidationError(
          expected: "String",
          found: value.classify(val),
          path: [],
        ),
      ])
    NumericType(numeric_type), _ -> validate_numeric_value(numeric_type, val)
    SemanticType(semantic_type), _ ->
      validate_semantic_value(semantic_type, val)
  }
}

/// Validates a Value matches the numeric type.
@internal
pub fn validate_numeric_value(
  numeric: NumericTypes,
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case numeric, val {
    Integer, value.IntValue(_) -> Ok(val)
    Integer, _ ->
      Error([
        ValidationError(expected: "Int", found: value.classify(val), path: []),
      ])
    Float, value.FloatValue(_) -> Ok(val)
    Float, _ ->
      Error([
        ValidationError(expected: "Float", found: value.classify(val), path: []),
      ])
  }
}

fn validate_semantic_value(
  typ: SemanticStringTypes,
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case typ, val {
    URL, value.StringValue(str) ->
      case validate_url(str) {
        Ok(Nil) -> Ok(val)
        Error(Nil) ->
          Error([
            ValidationError(
              expected: "URL (starting with http:// or https://)",
              found: str,
              path: [],
            ),
          ])
      }
    URL, _ ->
      Error([
        ValidationError(
          expected: "String",
          found: value.classify(val),
          path: [],
        ),
      ])
  }
}

fn validate_url(s: String) -> Result(Nil, Nil) {
  case string.starts_with(s, "http://") || string.starts_with(s, "https://") {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}

fn validate_collection_value(
  collection: CollectionTypes(AcceptedTypes),
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case collection {
    Dict(key_type, value_type) -> {
      case val {
        value.DictValue(dict_val) -> {
          dict_val
          |> dict.to_list
          |> list.try_map(fn(pair) {
            let #(k, v) = pair
            // Validate key
            use _ <- result.try(
              validate_value(key_type, value.StringValue(k))
              |> result.map_error(fn(errs) {
                list.map(errs, fn(e) {
                  ValidationError(..e, path: [k, ..e.path])
                })
              }),
            )
            // Validate value
            validate_value(value_type, v)
            |> result.map_error(fn(errs) {
              list.map(errs, fn(e) { ValidationError(..e, path: [k, ..e.path]) })
            })
          })
          |> result.map(fn(_) { val })
        }
        _ ->
          Error([
            ValidationError(
              expected: "Dict",
              found: value.classify(val),
              path: [],
            ),
          ])
      }
    }
    List(inner_type) -> {
      case val {
        value.ListValue(list_val) -> {
          list_val
          |> list.index_map(fn(v, i) { #(v, i) })
          |> list.try_map(fn(pair) {
            let #(v, i) = pair
            validate_value(inner_type, v)
            |> result.map_error(fn(errs) {
              list.map(errs, fn(e) {
                ValidationError(..e, path: [int.to_string(i), ..e.path])
              })
            })
          })
          |> result.map(fn(_) { val })
        }
        _ ->
          Error([
            ValidationError(
              expected: "List",
              found: value.classify(val),
              path: [],
            ),
          ])
      }
    }
  }
}

fn validate_modifier_value(
  modifier: ModifierTypes(AcceptedTypes),
  val: Value,
) -> Result(Value, List(ValidationError)) {
  // Both Optional and Defaulted validate identically: if a value is present,
  // validate it matches the inner type; if absent, accept as-is.
  let inner_type = case modifier {
    Optional(t) -> t
    Defaulted(t, _) -> t
  }
  case val {
    value.NilValue -> Ok(val)
    _ -> validate_value(inner_type, val)
  }
}

fn validate_refinement_value(
  refinement: RefinementTypes(AcceptedTypes),
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case refinement {
    OneOf(inner_type, allowed_values) -> {
      case value_to_type_string(inner_type, val) {
        Ok(str_val) -> {
          case set.contains(allowed_values, str_val) {
            True -> Ok(val)
            False ->
              Error([
                ValidationError(
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
      use as_str <- result.try(value_to_type_string(inner_type, val))
      let numeric = get_numeric_type(inner_type)
      case validate_in_range(numeric, as_str, low, high) {
        Ok(_) -> Ok(val)
        Error(errs) -> Error(errs)
      }
    }
  }
}

/// Converts a Value to its string representation based on the expected type.
/// Used internally for refinement validation and resolution.
fn value_to_type_string(
  typ: AcceptedTypes,
  val: Value,
) -> Result(String, List(ValidationError)) {
  case typ, val {
    PrimitiveType(Boolean), value.BoolValue(b) -> Ok(bool.to_string(b))
    PrimitiveType(String), value.StringValue(s) -> Ok(s)
    PrimitiveType(NumericType(Integer)), value.IntValue(i) ->
      Ok(int.to_string(i))
    PrimitiveType(NumericType(Float)), value.FloatValue(f) ->
      Ok(float.to_string(f))
    PrimitiveType(SemanticType(_)), value.StringValue(s) -> Ok(s)
    ModifierType(Optional(inner)), value.NilValue -> {
      // Absent optional resolves to empty string
      let _ = inner
      Ok("")
    }
    ModifierType(Defaulted(_, default_val)), value.NilValue -> Ok(default_val)
    ModifierType(Optional(inner)), _ -> value_to_type_string(inner, val)
    ModifierType(Defaulted(inner, _)), _ -> value_to_type_string(inner, val)
    _, _ ->
      Error([
        ValidationError(
          expected: accepted_type_to_string(typ),
          found: value.classify(val),
          path: [],
        ),
      ])
  }
}

/// Validates a default value is compatible with the primitive type.
@internal
pub fn validate_primitive_default_value(
  primitive: PrimitiveTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  case primitive {
    Boolean if default_val == "True" || default_val == "False" -> Ok(Nil)
    Boolean -> Error(Nil)
    String -> Ok(Nil)
    NumericType(numeric_type) ->
      validate_numeric_default_value(numeric_type, default_val)
    SemanticType(semantic_type) ->
      validate_semantic_default_value(semantic_type, default_val)
  }
}

/// Validates a default value is compatible with the numeric type.
@internal
pub fn validate_numeric_default_value(
  numeric: NumericTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  parse_numeric_string(numeric, default_val) |> result.replace(Nil)
}

fn parse_numeric_string(
  numeric: NumericTypes,
  value: String,
) -> Result(Float, Nil) {
  case numeric {
    Integer -> int.parse(value) |> result.map(int.to_float)
    Float -> float.parse(value)
  }
}

fn validate_semantic_default_value(
  typ: SemanticStringTypes,
  default_val: String,
) -> Result(Nil, Nil) {
  case typ {
    URL -> validate_url(default_val)
  }
}

/// Validates a default value for a modifier type by delegating to the inner type.
@internal
pub fn validate_modifier_default_value_recursive(
  modifier: ModifierTypes(AcceptedTypes),
  value: String,
  validate_inner: fn(AcceptedTypes, String) -> Result(Nil, Nil),
) -> Result(Nil, Nil) {
  case modifier {
    Defaulted(inner, _) -> validate_inner(inner, value)
    Optional(_) -> Error(Nil)
  }
}

/// Validates a default value is valid for a refinement type.
@internal
pub fn validate_refinement_default_value(
  refinement: RefinementTypes(AcceptedTypes),
  value: String,
  validate_inner_default: fn(AcceptedTypes, String) -> Result(Nil, Nil),
) -> Result(Nil, Nil) {
  case refinement {
    OneOf(_inner, allowed_values) ->
      case set.contains(allowed_values, value) {
        True -> Ok(Nil)
        False -> Error(Nil)
      }
    InclusiveRange(inner, low, high) -> {
      use _ <- result.try(validate_inner_default(inner, value))
      validate_in_range(get_numeric_type(inner), value, low, high)
      |> result.replace_error(Nil)
    }
  }
}

/// Validates a string value is within an inclusive range for the given numeric type.
@internal
pub fn validate_in_range(
  numeric: NumericTypes,
  value_str: String,
  low_str: String,
  high_str: String,
) -> Result(Nil, List(ValidationError)) {
  let type_name = numeric_type_to_string(numeric)
  case
    parse_numeric_string(numeric, value_str),
    parse_numeric_string(numeric, low_str),
    parse_numeric_string(numeric, high_str)
  {
    Ok(val), Ok(low), Ok(high) -> {
      case val >=. low, val <=. high {
        True, True -> Ok(Nil)
        _, _ ->
          Error([
            ValidationError(
              expected: low_str <> " <= x <= " <> high_str,
              found: value_str,
              path: [],
            ),
          ])
      }
    }
    _, _, _ ->
      Error([
        ValidationError(expected: type_name, found: value_str, path: []),
      ])
  }
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// Resolves a Value to a string using the provided resolver functions.
@internal
pub fn resolve_to_string(
  typ: AcceptedTypes,
  val: Value,
  resolve_string: fn(String) -> String,
  resolve_list: fn(List(String)) -> String,
) -> Result(String, String) {
  case typ {
    PrimitiveType(primitive) ->
      Ok(resolve_primitive_to_string(primitive, val, resolve_string))
    CollectionType(collection) ->
      resolve_collection_to_string(collection, val, resolve_list)
    ModifierType(modifier) ->
      resolve_modifier_to_string(modifier, val, resolve_string, resolve_list)
    RefinementType(refinement) ->
      resolve_refinement_to_string(refinement, val, resolve_string)
  }
}

/// Resolves a primitive value to a string using the provided resolver function.
@internal
pub fn resolve_primitive_to_string(
  primitive: PrimitiveTypes,
  val: Value,
  resolve_string: fn(String) -> String,
) -> String {
  let str = case primitive, val {
    Boolean, value.BoolValue(b) -> bool.to_string(b)
    String, value.StringValue(s) -> s
    NumericType(Integer), value.IntValue(i) -> int.to_string(i)
    NumericType(Float), value.FloatValue(f) -> float.to_string(f)
    SemanticType(_), value.StringValue(s) -> s
    _, _ -> value.to_string(val)
  }
  resolve_string(str)
}

fn resolve_collection_to_string(
  collection: CollectionTypes(AcceptedTypes),
  val: Value,
  resolve_list: fn(List(String)) -> String,
) -> Result(String, String) {
  case collection {
    Dict(_, _) ->
      Error(
        "Unsupported templatized variable type: "
        <> collection_type_to_string(collection)
        <> ". Dict support is pending, open an issue if this is a desired use case.",
      )
    List(inner_type) -> {
      case val {
        value.ListValue(items) -> {
          let vals =
            items
            |> list.map(fn(item) {
              case value_to_type_string(inner_type, item) {
                Ok(s) -> s
                Error(_) -> value.to_string(item)
              }
            })
          Ok(resolve_list(vals))
        }
        _ ->
          Error(
            "Failed to resolve list values for type: "
            <> collection_type_to_string(collection),
          )
      }
    }
  }
}

fn resolve_modifier_to_string(
  modifier: ModifierTypes(AcceptedTypes),
  val: Value,
  resolve_string: fn(String) -> String,
  resolve_list: fn(List(String)) -> String,
) -> Result(String, String) {
  case modifier {
    Optional(inner_type) -> {
      case val {
        value.NilValue -> Ok("")
        _ -> resolve_to_string(inner_type, val, resolve_string, resolve_list)
      }
    }
    Defaulted(inner_type, default_val) -> {
      case val {
        value.NilValue -> Ok(resolve_string(default_val))
        _ -> resolve_to_string(inner_type, val, resolve_string, resolve_list)
      }
    }
  }
}

fn resolve_refinement_to_string(
  refinement: RefinementTypes(AcceptedTypes),
  val: Value,
  resolve_string: fn(String) -> String,
) -> Result(String, String) {
  case refinement {
    OneOf(inner_type, _allowed_values) -> {
      case value_to_type_string(inner_type, val) {
        Ok(s) -> Ok(resolve_string(s))
        Error(_) -> Error("Unable to resolve OneOf refinement type value.")
      }
    }
    InclusiveRange(inner_type, _low, _high) -> {
      case value_to_type_string(inner_type, val) {
        Ok(s) -> Ok(resolve_string(s))
        Error(_) ->
          Error("Unable to resolve InclusiveRange refinement type value.")
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Traversal
// ---------------------------------------------------------------------------

/// Applies a fallible check to each inner type in a compound type.
/// For leaf types (PrimitiveType), calls the function directly.
/// For compound types (Collection, Modifier, Refinement), extracts inner types and applies the function.
@internal
pub fn try_each_inner(
  typ: AcceptedTypes,
  f: fn(AcceptedTypes) -> Result(Nil, e),
) -> Result(Nil, e) {
  case typ {
    PrimitiveType(_) -> f(typ)
    CollectionType(collection) -> collection_try_each_inner(collection, f)
    ModifierType(modifier) -> modifier_try_each_inner(modifier, f)
    RefinementType(refinement) -> refinement_try_each_inner(refinement, f)
  }
}

/// Transforms each inner type in a compound type using a mapping function.
@internal
pub fn map_inner(
  typ: AcceptedTypes,
  f: fn(AcceptedTypes) -> AcceptedTypes,
) -> AcceptedTypes {
  case typ {
    PrimitiveType(_) -> f(typ)
    CollectionType(collection) ->
      CollectionType(collection_map_inner(collection, f))
    ModifierType(modifier) -> ModifierType(modifier_map_inner(modifier, f))
    RefinementType(refinement) ->
      RefinementType(refinement_map_inner(refinement, f))
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

/// Extracts the NumericTypes from an AcceptedTypes.
/// Used by InclusiveRange validation - only Integer/Float primitives are valid.
///
/// INVARIANT: This function should only be called with types that are known to be
/// numeric (Integer or Float). The caller is responsible for ensuring this.
/// If a non-numeric type is passed, this returns Integer as a fallback but the
/// validation will likely fail with a type mismatch error upstream.
@internal
pub fn get_numeric_type(typ: AcceptedTypes) -> NumericTypes {
  case typ {
    PrimitiveType(NumericType(numeric)) -> numeric
    // InclusiveRange only allows Integer/Float, so these shouldn't happen
    // Fallback to Integer - upstream validation will catch the mismatch
    PrimitiveType(SemanticType(_)) -> Integer
    PrimitiveType(String) -> Integer
    PrimitiveType(Boolean) -> Integer
    CollectionType(_) -> Integer
    ModifierType(_) -> Integer
    RefinementType(_) -> Integer
  }
}

fn collection_try_each_inner(
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

fn collection_map_inner(
  collection: CollectionTypes(accepted),
  f: fn(accepted) -> accepted,
) -> CollectionTypes(accepted) {
  case collection {
    List(inner) -> List(f(inner))
    Dict(key, value) -> Dict(f(key), f(value))
  }
}

fn modifier_try_each_inner(
  modifier: ModifierTypes(accepted),
  f: fn(accepted) -> Result(Nil, e),
) -> Result(Nil, e) {
  case modifier {
    Optional(inner) -> f(inner)
    Defaulted(inner, _) -> f(inner)
  }
}

fn modifier_map_inner(
  modifier: ModifierTypes(accepted),
  f: fn(accepted) -> accepted,
) -> ModifierTypes(accepted) {
  case modifier {
    Optional(inner) -> Optional(f(inner))
    Defaulted(inner, default) -> Defaulted(f(inner), default)
  }
}

fn refinement_try_each_inner(
  refinement: RefinementTypes(accepted),
  f: fn(accepted) -> Result(Nil, e),
) -> Result(Nil, e) {
  case refinement {
    OneOf(inner, _) -> f(inner)
    InclusiveRange(inner, _, _) -> f(inner)
  }
}

fn refinement_map_inner(
  refinement: RefinementTypes(accepted),
  f: fn(accepted) -> accepted,
) -> RefinementTypes(accepted) {
  case refinement {
    OneOf(inner, values) -> OneOf(f(inner), values)
    InclusiveRange(inner, min, max) -> InclusiveRange(f(inner), min, max)
  }
}
