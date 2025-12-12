import caffeine_lang/common/errors.{type ParseError, FileReadError}
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import simplifile

/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Float
  Integer
  String
  Dict(AcceptedTypes, AcceptedTypes)
  List(AcceptedTypes)
  Optional(AcceptedTypes)
  /// Defaulted type stores the inner type and its default value as a string
  /// e.g., Defaulted(Integer, "10") means an optional integer with default 10
  Defaulted(AcceptedTypes, String)
}

/// A tuple of a label, type, and value used for template resolution.
pub type ValueTuple {
  ValueTuple(label: String, typ: AcceptedTypes, value: Dynamic)
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
    "Optional(String)" -> Ok(Optional(String))
    "Optional(Integer)" -> Ok(Optional(Integer))
    "Optional(Float)" -> Ok(Optional(Float))
    "Optional(Boolean)" -> Ok(Optional(Boolean))
    // Optional List types
    "Optional(List(String))" -> Ok(Optional(List(String)))
    "Optional(List(Integer))" -> Ok(Optional(List(Integer)))
    "Optional(List(Float))" -> Ok(Optional(List(Float)))
    "Optional(List(Boolean))" -> Ok(Optional(List(Boolean)))
    // Optional Dict types
    "Optional(Dict(String, String))" -> Ok(Optional(Dict(String, String)))
    "Optional(Dict(String, Integer))" -> Ok(Optional(Dict(String, Integer)))
    "Optional(Dict(String, Float))" -> Ok(Optional(Dict(String, Float)))
    "Optional(Dict(String, Boolean))" -> Ok(Optional(Dict(String, Boolean)))
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
                True -> Ok(Defaulted(inner_type, trimmed_default))
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
    Integer -> case int.parse(default_val) {
      Ok(_) -> True
      Error(_) -> False
    }
    Float -> case float.parse(default_val) {
      Ok(_) -> True
      Error(_) -> False
    }
    String -> True
    // For complex types, we accept any default since it's used as a literal
    // string value in template substitution
    List(_) -> True
    Dict(_, _) -> True
    // Nested Optional/Defaulted doesn't make sense
    Optional(_) -> False
    Defaulted(_, _) -> False
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
          find_type_default_split_helper(original, rest, index + 1, paren_depth + 1)
        ")", _ ->
          find_type_default_split_helper(original, rest, index + 1, paren_depth - 1)
        ",", 0 -> {
          // Found the split point at depth 0
          let type_str = string.slice(original, 0, index)
          let default_val = rest
          Ok(#(type_str, default_val))
        }
        _, _ -> find_type_default_split_helper(original, rest, index + 1, paren_depth)
      }
    }
  }
}

/// Converts an AcceptedTypes to its string representation.
pub fn accepted_type_to_string(accepted_type: AcceptedTypes) -> String {
  case accepted_type {
    Boolean -> "Boolean"
    Float -> "Float"
    Integer -> "Integer"
    String -> "String"
    Dict(key_type, value_type) ->
      "Dict("
      <> accepted_type_to_string(key_type)
      <> ", "
      <> accepted_type_to_string(value_type)
      <> ")"
    List(inner_type) -> "List(" <> accepted_type_to_string(inner_type) <> ")"
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

/// Reads the contents of a JSON file as a string.
pub fn json_from_file(file_path) -> Result(String, ParseError) {
  case simplifile.read(file_path) {
    Ok(file_contents) -> Ok(file_contents)
    Error(err) ->
      Error(FileReadError(
        msg: simplifile.describe_error(err) <> " (" <> file_path <> ")",
      ))
  }
}

/// A helper for chaining Result operations with the `use` syntax.
/// Equivalent to `result.try` but defined here for convenient use with `use`.
pub fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

/// Maps each referrer to its corresponding reference by matching names.
/// Returns a list of tuples pairing each referrer with its matched reference.
pub fn map_reference_to_referrer_over_collection(
  references references: List(a),
  referrers referrers: List(b),
  reference_name reference_name: fn(a) -> String,
  referrer_reference referrer_reference: fn(b) -> String,
) {
  referrers
  |> list.map(fn(referrer) {
    // already performed this check so can assert it
    let assert Ok(reference) =
      references
      |> list.filter(fn(reference) {
        { reference |> reference_name } == { referrer |> referrer_reference }
      })
      |> list.first
    #(referrer, reference)
  })
}
