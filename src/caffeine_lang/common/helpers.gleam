import caffeine_lang/common/errors.{type ParseError, FileReadError}
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option
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
      use maybe_val <- decode.then(decode.optional(decode_value_to_string(
        inner_type,
      )))
      case maybe_val {
        option.Some(val) -> decode.success(val)
        option.None -> decode.success("")
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
    // TODO: hacky, fix this
    _ -> Error(Nil)
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
  }
}

/// Reads the contents of a JSON file as a string.
pub fn json_from_file(file_path) -> Result(String, ParseError) {
  case simplifile.read(file_path) {
    Ok(file_contents) -> Ok(file_contents)
    Error(err) ->
      Error(FileReadError(msg: simplifile.describe_error(err)
        <> " ("
        <> file_path
        <> ")"))
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
