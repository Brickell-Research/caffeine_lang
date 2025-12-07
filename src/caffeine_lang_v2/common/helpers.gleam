import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/set
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
      "Incorrect types: "
      <> suberrors |> format_decode_error_message(option.None)
    }
  }
}

pub fn format_decode_error_message(
  errors: List(decode.DecodeError),
  type_key_identifier: option.Option(String),
) -> String {
  errors
  |> list.map(fn(error) {
    "expected ("
    <> error.expected
    <> ") received ("
    <> error.found
    <> ") for ("
    <> {
      case { error.path |> string.join(".") }, type_key_identifier {
        "", option.None -> "Unknown"
        _, option.None -> {
          error.path |> string.join(".")
        }
        "", option.Some(val) -> val
        _, _ -> {
          error.path |> string.join(".")
        }
      }
    }
    <> ")"
  })
  |> string.join(", ")
}

pub fn validate_value_type(
  value: dynamic.Dynamic,
  expected_type: AcceptedTypes,
  type_key_identifier: String,
) -> Result(dynamic.Dynamic, ParseError) {
  case expected_type {
    Boolean -> {
      case decode.run(value, decode.bool) {
        Ok(_) -> Ok(value)
        Error(err) ->
          Error(
            JsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    Integer -> {
      case decode.run(value, decode.int) {
        Ok(_) -> Ok(value)
        Error(err) ->
          Error(
            JsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    Float -> {
      case decode.run(value, decode.float) {
        Ok(_) -> Ok(value)
        Error(err) ->
          Error(
            JsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    String -> {
      case decode.run(value, decode.string) {
        Ok(_) -> Ok(value)
        Error(err) ->
          Error(
            JsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    Dict(_key_type, value_type) -> {
      case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
        Ok(dict_val) -> {
          dict_val
          |> dict.values
          |> list.try_map(fn(v) {
            validate_value_type(v, value_type, type_key_identifier)
          })
          |> result.map(fn(_) { value })
        }
        Error(err) ->
          Error(
            JsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    List(inner_type) -> {
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(list_val) -> {
          list_val
          |> list.try_map(fn(v) {
            validate_value_type(v, inner_type, type_key_identifier)
          })
          |> result.map(fn(_) { value })
        }
        Error(err) ->
          Error(
            JsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
  }
}

pub fn inputs_validator(
  params params: Dict(String, AcceptedTypes),
  inputs inputs: Dict(String, Dynamic),
) -> Result(Bool, String) {
  let param_keys = params |> dict.keys |> set.from_list
  let input_keys = inputs |> dict.keys |> set.from_list

  let keys_only_in_params =
    set.difference(param_keys, input_keys) |> set.to_list
  let keys_only_in_inputs =
    set.difference(input_keys, param_keys) |> set.to_list

  // see if we have the same inputs and params
  use _ <- result.try(case keys_only_in_params, keys_only_in_inputs {
    [], [] -> Ok(True)
    _, [] ->
      Error(
        "Missing keys in input: "
        <> { keys_only_in_params |> string.join(", ") },
      )
    [], _ ->
      Error(
        "Extra keys in input: " <> { keys_only_in_inputs |> string.join(", ") },
      )
    _, _ ->
      Error(
        "Extra keys in input: "
        <> { keys_only_in_inputs |> string.join(", ") }
        <> " and missing keys in input: "
        <> { keys_only_in_params |> string.join(", ") },
      )
  })

  let type_validation_errors =
    inputs
    |> dict.to_list
    |> list.filter_map(fn(pair) {
      let #(key, value) = pair
      let assert Ok(expected_type) = params |> dict.get(key)

      case validate_value_type(value, expected_type, key) {
        Ok(_) -> Error(Nil)
        Error(errs) -> Ok(errs)
      }
    })
    |> list.map(fn(err) { err.msg })
    |> string.join(", ")

  case type_validation_errors {
    "" -> Ok(True)
    _ -> Error(type_validation_errors)
  }
}
