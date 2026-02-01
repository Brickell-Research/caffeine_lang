import caffeine_lang/common/parsing_utils
import caffeine_lang/common/type_info.{type TypeMeta, TypeMeta}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/option
import gleam/result

/// Modifier types are a special class of types that alter the value semantics of
/// the attribute they are bound to.
pub type ModifierTypes(accepted) {
  Optional(accepted)
  /// Defaulted type stores the inner type and its default value as a string
  /// e.g., Defaulted(Integer, "10") means an optional integer with default 10
  Defaulted(accepted, String)
}

/// Returns metadata for all ModifierTypes variants.
/// IMPORTANT: Update this when adding new variants!
@internal
pub fn all_type_metas() -> List(TypeMeta) {
  [modifier_type_meta(Optional(Nil)), modifier_type_meta(Defaulted(Nil, ""))]
}

/// Returns metadata for a ModifierTypes variant.
/// Exhaustive pattern matching ensures new types must have descriptions.
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

/// Converts a ModifierTypes to its string representation.
@internal
pub fn modifier_type_to_string(
  modifier_type: ModifierTypes(accepted),
  accepted_type_to_string: fn(accepted) -> String,
) -> String {
  case modifier_type {
    Optional(inner_type) ->
      "Optional(" <> accepted_type_to_string(inner_type) <> ")"
    Defaulted(inner_type, default_val) ->
      "Defaulted("
      <> accepted_type_to_string(inner_type)
      <> ", "
      <> default_val
      <> ")"
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

/// Applies a fallible check to the inner type of a modifier type.
@internal
pub fn try_each_inner(
  modifier: ModifierTypes(accepted),
  f: fn(accepted) -> Result(Nil, e),
) -> Result(Nil, e) {
  case modifier {
    Optional(inner) -> f(inner)
    Defaulted(inner, _) -> f(inner)
  }
}

/// Transforms the inner type of a modifier type using a mapping function.
@internal
pub fn map_inner(
  modifier: ModifierTypes(accepted),
  f: fn(accepted) -> accepted,
) -> ModifierTypes(accepted) {
  case modifier {
    Optional(inner) -> Optional(f(inner))
    Defaulted(inner, default) -> Defaulted(f(inner), default)
  }
}

/// Validates a default value for a modifier type by delegating to the inner type.
/// The validate_inner callback lets the parent validate inner type defaults
/// without creating a circular dependency.
@internal
pub fn validate_default_value_recursive(
  modifier: ModifierTypes(accepted),
  value: String,
  validate_inner: fn(accepted, String) -> Result(Nil, Nil),
) -> Result(Nil, Nil) {
  case modifier {
    Defaulted(inner, _) -> validate_inner(inner, value)
    Optional(_) -> Error(Nil)
  }
}

/// Decoder that converts a dynamic modifier value to its String representation.
@internal
pub fn decode_modifier_to_string(
  modifier: ModifierTypes(accepted),
  decode_inner: fn(accepted) -> decode.Decoder(String),
) -> decode.Decoder(String) {
  case modifier {
    Optional(inner_type) -> {
      use maybe_val <- decode.then(decode.optional(decode_inner(inner_type)))
      decode.success(option.unwrap(maybe_val, ""))
    }
    Defaulted(inner_type, default_val) -> {
      use maybe_val <- decode.then(decode.optional(decode_inner(inner_type)))
      decode.success(option.unwrap(maybe_val, default_val))
    }
  }
}

/// Validates a dynamic value matches the modifier type.
/// Returns the original value if valid, or an error with decode errors.
@internal
pub fn validate_value(
  modifier: ModifierTypes(accepted),
  value: Dynamic,
  validate_inner: fn(accepted, Dynamic) ->
    Result(Dynamic, List(decode.DecodeError)),
) -> Result(Dynamic, List(decode.DecodeError)) {
  // Both Optional and Defaulted validate identically: if a value is present,
  // validate it matches the inner type; if absent, accept as-is.
  let inner_type = case modifier {
    Optional(t) -> t
    Defaulted(t, _) -> t
  }
  case decode.run(value, decode.optional(decode.dynamic)) {
    Ok(option.Some(inner_val)) -> validate_inner(inner_type, inner_val)
    Ok(option.None) -> Ok(value)
    Error(err) -> Error(err)
  }
}

/// Resolves a modifier value to a string using the provided resolver function.
/// For Optional: returns "" if None, otherwise resolves inner value.
/// For Defaulted: returns default if None, otherwise resolves inner value.
@internal
pub fn resolve_to_string(
  modifier: ModifierTypes(accepted),
  value: Dynamic,
  resolve_inner: fn(accepted, Dynamic) -> Result(String, String),
  resolve_string: fn(String) -> String,
) -> Result(String, String) {
  case modifier {
    Optional(inner_type) -> {
      case decode.run(value, decode.optional(decode.dynamic)) {
        Ok(option.Some(inner_val)) -> resolve_inner(inner_type, inner_val)
        Ok(option.None) -> Ok("")
        Error(_) -> Ok("")
      }
    }
    Defaulted(inner_type, default_val) -> {
      case decode.run(value, decode.optional(decode.dynamic)) {
        Ok(option.Some(inner_val)) -> resolve_inner(inner_type, inner_val)
        Ok(option.None) -> Ok(resolve_string(default_val))
        Error(_) -> Ok(resolve_string(default_val))
      }
    }
  }
}
