import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Float
  Integer
  String
  Dict(AcceptedTypes, AcceptedTypes)
  NonEmptyList(AcceptedTypes)
  Optional(AcceptedTypes)
  NoValue
}

pub fn accepted_types_decoder() -> decode.Decoder(AcceptedTypes) {
  decode.new_primitive_decoder("AcceptedType", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok(x) ->
        case parse_accepted_type(x) {
          Ok(x) -> Ok(x)
          Error(_) -> Error(NoValue)
        }
      _ -> Error(NoValue)
    }
  })
}

/// Parses a raw string into an AcceptedType.
fn parse_accepted_type(
  raw_accepted_type,
) -> Result(AcceptedTypes, AcceptedTypes) {
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
    // NonEmptyList types
    "NonEmptyList(String)" -> Ok(NonEmptyList(String))
    "NonEmptyList(Integer)" -> Ok(NonEmptyList(Integer))
    "NonEmptyList(Boolean)" -> Ok(NonEmptyList(Boolean))
    "NonEmptyList(Float)" -> Ok(NonEmptyList(Float))
    // Optional types
    "Optional(String)" -> Ok(Optional(String))
    "Optional(Integer)" -> Ok(Optional(Integer))
    "Optional(Boolean)" -> Ok(Optional(Boolean))
    "Optional(Float)" -> Ok(Optional(Float))
    // Optional NonEmptyList types
    "Optional(NonEmptyList(String))" -> Ok(Optional(NonEmptyList(String)))
    "Optional(NonEmptyList(Integer))" -> Ok(Optional(NonEmptyList(Integer)))
    "Optional(NonEmptyList(Boolean))" -> Ok(Optional(NonEmptyList(Boolean)))
    "Optional(NonEmptyList(Float))" -> Ok(Optional(NonEmptyList(Float)))
    // Optional Dict types
    "Optional(Dict(String, String))" -> Ok(Optional(Dict(String, String)))
    "Optional(Dict(String, Integer))" -> Ok(Optional(Dict(String, Integer)))
    "Optional(Dict(String, Float))" -> Ok(Optional(Dict(String, Float)))
    "Optional(Dict(String, Boolean))" -> Ok(Optional(Dict(String, Boolean)))
    // TODO: hacky, fix thi
    _ -> Error(NoValue)
  }
}

pub type ParseError {
  FileReadError(msg: String)
  JsonParserError(msg: String)
  DuplicateError(msg: String)
}

pub fn format_json_decode_error(error: json.DecodeError) -> ParseError {
  let msg = json_error_to_string(error)

  JsonParserError(msg:)
}

fn json_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "Unexpected end of input."
    json.UnexpectedByte(val) -> "Unexpected byte: " <> val <> "."
    json.UnexpectedSequence(val) -> "Unexpected sequence: " <> val <> "."
    json.UnableToDecode(suberrors) -> {
      "Incorrect types: "
      <> suberrors
      |> list.map(fn(err) {
        "expected ("
        <> err.expected
        <> ") received ("
        <> err.found
        <> ") for ("
        <> { err.path |> string.join(".") }
        <> ")"
      })
      |> string.join(", ")
    }
  }
}
