import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
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
  List(AcceptedTypes)
}

pub fn accepted_types_decoder() -> decode.Decoder(AcceptedTypes) {
  use raw_string <- decode.then(decode.string)
  case parse_accepted_type(raw_string) {
    Ok(t) -> decode.success(t)
    Error(Nil) -> decode.failure(Boolean, "AcceptedType")
  }
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
    // TODO: hacky, fix this
    _ -> Error(Nil)
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
      "Incorrect types: " <> suberrors |> format_decode_error_message
    }
  }
}

pub fn format_decode_error_message(errors: List(decode.DecodeError)) -> String {
  errors
  |> list.map(fn(error) {
    "expected ("
    <> error.expected
    <> ") received ("
    <> error.found
    <> ") for ("
    <> { error.path |> string.join(".") }
    <> ")"
  })
  |> string.join(", ")
}

pub fn validate_value_type(
  value: dynamic.Dynamic,
  expected_type: AcceptedTypes,
) -> Result(dynamic.Dynamic, ParseError) {
  case expected_type {
    Boolean -> {
      case decode.run(value, decode.bool) {
        Ok(_) -> Ok(value)
        Error(err) -> Error(JsonParserError(format_decode_error_message(err)))
      }
    }
    Integer -> {
      case decode.run(value, decode.int) {
        Ok(_) -> Ok(value)
        Error(err) -> Error(JsonParserError(format_decode_error_message(err)))
      }
    }
    Float -> {
      case decode.run(value, decode.float) {
        Ok(_) -> Ok(value)
        Error(err) -> Error(JsonParserError(format_decode_error_message(err)))
      }
    }
    String -> {
      case decode.run(value, decode.string) {
        Ok(_) -> Ok(value)
        Error(err) -> Error(JsonParserError(format_decode_error_message(err)))
      }
    }
    Dict(_key_type, value_type) -> {
      case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
        Ok(dict_val) -> {
          dict_val
          |> dict.values
          |> list.try_map(fn(v) { validate_value_type(v, value_type) })
          |> result.map(fn(_) { value })
        }
        Error(err) -> Error(JsonParserError(format_decode_error_message(err)))
      }
    }
    List(inner_type) -> {
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(list_val) -> {
          list_val
          |> list.try_map(fn(v) { validate_value_type(v, inner_type) })
          |> result.map(fn(_) { value })
        }
        Error(err) -> Error(JsonParserError(format_decode_error_message(err)))
      }
    }
  }
}
