import caffeine_lang/common/accepted_types.{
  type AcceptedTypes, Boolean, Defaulted, Dict, Float, Integer, List, Modifier,
  Optional, String,
}
import gleam/bool
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/string

/// Creates a decoder that validates a string is a valid reference to an item in a collection.
/// Returns the string if it matches a name in the collection, otherwise fails decoding.
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

/// Decoder for AcceptedTypes from a raw string representation.
/// i.e. for "Dict(String, String)" will return a decoder for 
/// Ok(helpers.Dict(helpers.String, helpers.String))).
/// 
/// Note that the default for the error is decode.failure(Boolean, "AcceptedType")
/// which is a bit odd, but nonetheless should do the job for now.
pub fn accepted_types_decoder() -> decode.Decoder(AcceptedTypes) {
  use raw_string <- decode.then(decode.string)
  case parse_accepted_type(raw_string) {
    Ok(t) -> decode.success(t)
    Error(Nil) -> decode.failure(Boolean, "AcceptedType")
  }
}

/// Decoder that decodes a dynamic value based on an AcceptedTypes and returns its String representation.
pub fn decode_value_to_string(typ: AcceptedTypes) -> decode.Decoder(String) {
  case typ {
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
    Dict(_, _) -> decode.failure("", "Dict")
    List(_) -> decode.failure("", "List")
    Modifier(modifier_type) ->
      case modifier_type {
        Optional(inner_type) -> {
          use maybe_val <- decode.then(
            decode.optional(decode_value_to_string(inner_type)),
          )
          case maybe_val {
            option.Some(val) -> decode.success(val)
            option.None -> decode.success("")
          }
        }
        Defaulted(inner_type, default_val) -> {
          use maybe_val <- decode.then(
            decode.optional(decode_value_to_string(inner_type)),
          )
          case maybe_val {
            option.Some(val) -> decode.success(val)
            option.None -> decode.success(default_val)
          }
        }
      }
  }
}

/// Decoder that decodes a list of dynamic values and returns a List(String).
pub fn decode_list_values_to_strings(
  inner_type: AcceptedTypes,
) -> decode.Decoder(List(String)) {
  decode.list(decode_value_to_string(inner_type))
}

/// Parses a raw string into an AcceptedType.
fn parse_accepted_type(raw_accepted_type) -> Result(AcceptedTypes, Nil) {
  case raw_accepted_type {
    // Basic types
    "Boolean" -> Ok(Boolean)
    "Float" -> Ok(Float)
    "Integer" -> Ok(Integer)
    "String" -> Ok(String)
    // Dict types
    "Dict(String, String)" -> Ok(Dict(String, String))
    "Dict(String, Integer)" -> Ok(Dict(String, Integer))
    "Dict(String, Float)" -> Ok(Dict(String, Float))
    "Dict(String, Boolean)" -> Ok(Dict(String, Boolean))
    // List types
    "List(String)" -> Ok(List(String))
    "List(Integer)" -> Ok(List(Integer))
    "List(Boolean)" -> Ok(List(Boolean))
    "List(Float)" -> Ok(List(Float))
    // Optional types
    "Optional(String)" -> Ok(Modifier(Optional(String)))
    "Optional(Integer)" -> Ok(Modifier(Optional(Integer)))
    "Optional(Float)" -> Ok(Modifier(Optional(Float)))
    "Optional(Boolean)" -> Ok(Modifier(Optional(Boolean)))
    // Optional List types
    "Optional(List(String))" -> Ok(Modifier(Optional(List(String))))
    "Optional(List(Integer))" -> Ok(Modifier(Optional(List(Integer))))
    "Optional(List(Float))" -> Ok(Modifier(Optional(List(Float))))
    "Optional(List(Boolean))" -> Ok(Modifier(Optional(List(Boolean))))
    // Optional Dict types
    "Optional(Dict(String, String))" ->
      Ok(Modifier(Optional(Dict(String, String))))
    "Optional(Dict(String, Integer))" ->
      Ok(Modifier(Optional(Dict(String, Integer))))
    "Optional(Dict(String, Float))" ->
      Ok(Modifier(Optional(Dict(String, Float))))
    "Optional(Dict(String, Boolean))" ->
      Ok(Modifier(Optional(Dict(String, Boolean))))
    // Try to parse Defaulted types with default value
    _ -> parse_defaulted_type(raw_accepted_type)
  }
}

/// Parses a Defaulted type string like "Defaulted(Integer, 10)" into Defaulted(Integer, "10")
/// Also validates that the default value is compatible with the inner type.
fn parse_defaulted_type(raw: String) -> Result(AcceptedTypes, Nil) {
  case string.starts_with(raw, "Defaulted(") && string.ends_with(raw, ")") {
    False -> Error(Nil)
    True -> {
      // Remove "Defaulted(" prefix and ")" suffix
      let inner =
        raw
        |> string.drop_start(10)
        |> string.drop_end(1)

      // Find the last comma that separates the type from the default value
      // We need to handle nested types like "List(String), default"
      case find_type_default_split(inner) {
        Error(Nil) -> Error(Nil)
        Ok(#(type_str, default_val)) -> {
          let trimmed_type = string.trim(type_str)
          let trimmed_default = string.trim(default_val)
          case parse_accepted_type(trimmed_type) {
            Ok(inner_type) -> {
              // Validate the default value is compatible with the inner type
              case validate_default_value(inner_type, trimmed_default) {
                True -> Ok(Modifier(Defaulted(inner_type, trimmed_default)))
                False -> Error(Nil)
              }
            }
            Error(Nil) -> Error(Nil)
          }
        }
      }
    }
  }
}

/// Validates that a default value string is compatible with the given type.
/// For basic types, checks that the string can be parsed as that type.
/// For complex types (List, Dict), we accept any string since the default
/// is used as a literal string value in templates.
fn validate_default_value(typ: AcceptedTypes, default_val: String) -> Bool {
  case typ {
    Boolean -> default_val == "True" || default_val == "False"
    Integer ->
      case int.parse(default_val) {
        Ok(_) -> True
        Error(_) -> False
      }
    Float ->
      case float.parse(default_val) {
        Ok(_) -> True
        Error(_) -> False
      }
    String -> True
    // For complex types, we accept any default since it's used as a literal
    // string value in template substitution
    List(_) -> True
    Dict(_, _) -> True
    // Nested Optional/Defaulted doesn't make sense
    Modifier(_) -> False
  }
}

/// Finds the split point between the type and default value in a Defaulted inner string.
/// For "Integer, 10" returns Ok(#("Integer", "10"))
/// For "List(String), hello" returns Ok(#("List(String)", "hello"))
/// Handles nested parentheses correctly.
fn find_type_default_split(inner: String) -> Result(#(String, String), Nil) {
  find_type_default_split_helper(inner, inner, 0, 0)
}

fn find_type_default_split_helper(
  original: String,
  s: String,
  index: Int,
  paren_depth: Int,
) -> Result(#(String, String), Nil) {
  case string.pop_grapheme(s) {
    Error(Nil) -> Error(Nil)
    Ok(#(char, rest)) -> {
      case char, paren_depth {
        "(", _ ->
          find_type_default_split_helper(
            original,
            rest,
            index + 1,
            paren_depth + 1,
          )
        ")", _ ->
          find_type_default_split_helper(
            original,
            rest,
            index + 1,
            paren_depth - 1,
          )
        ",", 0 -> {
          // Found the split point at depth 0
          let type_str = string.slice(original, 0, index)
          let default_val = rest
          Ok(#(type_str, default_val))
        }
        _, _ ->
          find_type_default_split_helper(original, rest, index + 1, paren_depth)
      }
    }
  }
}
