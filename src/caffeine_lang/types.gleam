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
  RecordType(dict.Dict(String, AcceptedTypes))
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
  /// A record type with named, typed fields.
  ParsedRecord(dict.Dict(String, ParsedType))
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
  Percentage
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
pub fn all_type_metas() -> List(TypeMeta) {
  list.flatten([
    completable_type_metas(),
    structured_all_type_metas(),
    refinement_all_type_metas(),
  ])
}

/// Returns type metadata for types that can be used directly in type position.
/// Excludes refinement types (OneOf, InclusiveRange) since those are syntactic
/// modifiers applied to other types (e.g. `String { x | x in { a, b } }`),
/// not standalone type names a user would type.
pub fn completable_type_metas() -> List(TypeMeta) {
  list.flatten([
    primitive_all_type_metas(),
    collection_all_type_metas(),
    modifier_all_type_metas(),
  ])
}

/// Returns type metadata for all primitive types.
pub fn primitive_all_type_metas() -> List(TypeMeta) {
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
  [
    numeric_type_meta(Integer),
    numeric_type_meta(Float),
    numeric_type_meta(Percentage),
  ]
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
    Percentage ->
      TypeMeta(
        name: "Percentage",
        description: "A numeric value between 0.0 and 100.0 representing a percentage",
        syntax: "Percentage",
        example: "99.9%",
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

/// Returns type metadata for all collection types.
pub fn collection_all_type_metas() -> List(TypeMeta) {
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

/// Returns type metadata for all modifier types.
pub fn modifier_all_type_metas() -> List(TypeMeta) {
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

/// Returns type metadata for all refinement types.
pub fn refinement_all_type_metas() -> List(TypeMeta) {
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

/// Returns type metadata for structured types (Record).
pub fn structured_all_type_metas() -> List(TypeMeta) {
  [
    TypeMeta(
      name: "Record",
      description: "A group of named, typed fields",
      syntax: "{ field: T, ... }",
      example: "{ numerator: String, denominator: String }",
    ),
  ]
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
    RecordType(fields) -> record_type_to_string(fields)
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
@internal
pub fn numeric_type_to_string(numeric_type: NumericTypes) -> String {
  case numeric_type {
    Float -> "Float"
    Integer -> "Integer"
    Percentage -> "Percentage"
  }
}

/// Converts a SemanticStringTypes to its string representation.
@internal
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

/// Converts a record type to its string representation.
fn record_type_to_string(fields: dict.Dict(String, AcceptedTypes)) -> String {
  let field_strs =
    fields
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.0 <> ": " <> accepted_type_to_string(pair.1) })
  "{ " <> string.join(field_strs, ", ") <> " }"
}

/// Converts a parsed record type to its string representation.
fn parsed_record_to_string(fields: dict.Dict(String, ParsedType)) -> String {
  let field_strs =
    fields
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.0 <> ": " <> parsed_type_to_string(pair.1) })
  "{ " <> string.join(field_strs, ", ") <> " }"
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
    ParsedRecord(fields) -> parsed_record_to_string(fields)
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
    ParsedRecord(fields) -> dict.values(fields) |> list.try_each(f)
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
    RecordType(fields) -> validate_record_value(fields, val)
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
    Percentage, value.PercentageValue(f) ->
      case f >=. 0.0 && f <=. 100.0 {
        True -> Ok(val)
        False ->
          Error([
            ValidationError(
              expected: "Percentage (0.0 <= x <= 100.0)",
              found: float.to_string(f),
              path: [],
            ),
          ])
      }
    Percentage, value.FloatValue(_) ->
      Error([
        ValidationError(
          expected: "Percentage (use % suffix, e.g. 99.9%)",
          found: value.classify(val),
          path: [],
        ),
      ])
    Percentage, _ ->
      Error([
        ValidationError(
          expected: "Percentage",
          found: value.classify(val),
          path: [],
        ),
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

fn validate_record_value(
  schema: dict.Dict(String, AcceptedTypes),
  val: Value,
) -> Result(Value, List(ValidationError)) {
  case val {
    value.DictValue(dict_val) -> {
      // Reject extra fields not in schema
      let schema_keys = dict.keys(schema) |> set.from_list
      let val_keys = dict.keys(dict_val) |> set.from_list
      let extra_keys = set.difference(val_keys, schema_keys)
      use <- bool.guard(
        !set.is_empty(extra_keys),
        Error([
          ValidationError(
            expected: "only fields: "
              <> schema_keys
            |> set.to_list
            |> list.sort(string.compare)
            |> string.join(", "),
            found: "unexpected field(s): "
              <> extra_keys
            |> set.to_list
            |> list.sort(string.compare)
            |> string.join(", "),
            path: [],
          ),
        ]),
      )
      // For each schema field: validate it exists and type-check
      schema
      |> dict.to_list
      |> list.try_map(fn(pair) {
        let #(field_name, field_type) = pair
        case dict.get(dict_val, field_name) {
          Ok(field_val) ->
            validate_value(field_type, field_val)
            |> result.map_error(fn(errs) {
              list.map(errs, fn(e) {
                ValidationError(..e, path: [field_name, ..e.path])
              })
            })
          Error(_) ->
            case is_optional_or_defaulted(field_type) {
              True -> Ok(value.NilValue)
              False ->
                Error([
                  ValidationError(
                    expected: accepted_type_to_string(field_type),
                    found: "missing field",
                    path: [field_name],
                  ),
                ])
            }
        }
      })
      |> result.map(fn(_) { val })
    }
    _ ->
      Error([
        ValidationError(
          expected: "Record",
          found: value.classify(val),
          path: [],
        ),
      ])
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
    PrimitiveType(Boolean), value.BoolValue(True) -> Ok("true")
    PrimitiveType(Boolean), value.BoolValue(False) -> Ok("false")
    PrimitiveType(String), value.StringValue(s) -> Ok(s)
    PrimitiveType(NumericType(Integer)), value.IntValue(i) ->
      Ok(int.to_string(i))
    PrimitiveType(NumericType(Float)), value.FloatValue(f) ->
      Ok(float.to_string(f))
    PrimitiveType(NumericType(Percentage)), value.PercentageValue(f) ->
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

fn parse_numeric_string(
  numeric: NumericTypes,
  value: String,
) -> Result(Float, Nil) {
  case numeric {
    Integer -> int.parse(value) |> result.map(int.to_float)
    Float -> float.parse(value)
    Percentage -> {
      // Strip optional % suffix before parsing as float
      let cleaned = case string.ends_with(value, "%") {
        True -> string.drop_end(value, 1)
        False -> value
      }
      float.parse(cleaned)
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
    RecordType(_) -> Error("Record types cannot be template variables")
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
    Boolean, value.BoolValue(True) -> "true"
    Boolean, value.BoolValue(False) -> "false"
    String, value.StringValue(s) -> s
    NumericType(Integer), value.IntValue(i) -> int.to_string(i)
    NumericType(Float), value.FloatValue(f) -> float.to_string(f)
    NumericType(Percentage), value.PercentageValue(f) -> float.to_string(f)
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
        value.NilValue ->
          resolve_default_value_to_string(
            inner_type,
            default_val,
            resolve_string,
            resolve_list,
          )
        _ -> resolve_to_string(inner_type, val, resolve_string, resolve_list)
      }
    }
  }
}

/// Turns a Defaulted's stored default-string into a resolved output. Routes through
/// resolve_list when the inner type is a List so list-typed defaults render as
/// `IN (...)` rather than getting concatenated as one opaque string. Other types
/// fall through to resolve_string (the historical behavior).
fn resolve_default_value_to_string(
  inner_type: AcceptedTypes,
  default_val: String,
  resolve_string: fn(String) -> String,
  resolve_list: fn(List(String)) -> String,
) -> Result(String, String) {
  case inner_type {
    CollectionType(List(_)) ->
      Ok(resolve_list(parse_list_default_string(default_val)))
    _ -> Ok(resolve_string(default_val))
  }
}

/// Parses a serialized list default like "[200]" or "[a, b]" back into its element
/// strings. Returns the original string wrapped in a single-element list as a
/// best-effort fallback if it isn't bracket-delimited. Does not preserve commas
/// embedded inside individual string elements.
@internal
pub fn parse_list_default_string(default_val: String) -> List(String) {
  let trimmed = string.trim(default_val)
  case string.starts_with(trimmed, "["), string.ends_with(trimmed, "]") {
    True, True -> {
      let inner =
        trimmed
        |> string.drop_start(1)
        |> string.drop_end(1)
        |> string.trim
      case inner {
        "" -> []
        _ -> inner |> string.split(",") |> list.map(string.trim)
      }
    }
    _, _ -> [default_val]
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

/// Checks if a type is optional or has a default value.
/// Recurses through OneOf refinement types to check the inner type.
@internal
pub fn is_optional_or_defaulted(typ: AcceptedTypes) -> Bool {
  case typ {
    ModifierType(Optional(_)) -> True
    ModifierType(Defaulted(_, _)) -> True
    RefinementType(OneOf(inner, _)) -> is_optional_or_defaulted(inner)
    RecordType(_) -> False
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
    RecordType(_) -> Integer
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

fn modifier_try_each_inner(
  modifier: ModifierTypes(accepted),
  f: fn(accepted) -> Result(Nil, e),
) -> Result(Nil, e) {
  case modifier {
    Optional(inner) -> f(inner)
    Defaulted(inner, _) -> f(inner)
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
