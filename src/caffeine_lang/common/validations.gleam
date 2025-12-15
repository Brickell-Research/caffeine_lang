import caffeine_lang/common/errors.{
  type CompilationError, ParserDuplicateError, ParserJsonParserError,
  format_decode_error_message,
}
import caffeine_lang/common/helpers.{type AcceptedTypes, Boolean, Integer}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string

/// Validates that a dynamic value matches the expected AcceptedType.
/// Returns the original value if valid, or a CompilationError describing the type mismatch.
pub fn validate_value_type(
  value: dynamic.Dynamic,
  expected_type: AcceptedTypes,
  type_key_identifier: String,
) -> Result(dynamic.Dynamic, CompilationError) {
  case expected_type {
    Boolean ->
      validate_value_type_helper(value, decode.bool, type_key_identifier)
    Integer ->
      validate_value_type_helper(value, decode.int, type_key_identifier)
    helpers.Float ->
      validate_value_type_helper(value, decode.float, type_key_identifier)
    helpers.String ->
      validate_value_type_helper(value, decode.string, type_key_identifier)
    helpers.Dict(_key_type, value_type) -> {
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
            ParserJsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    helpers.List(inner_type) -> {
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
            ParserJsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    helpers.Optional(inner_type) -> {
      case decode.run(value, decode.optional(decode.dynamic)) {
        Ok(option.Some(inner_val)) ->
          validate_value_type(inner_val, inner_type, type_key_identifier)
        Ok(option.None) -> Ok(value)
        Error(err) ->
          Error(
            ParserJsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
    helpers.Defaulted(inner_type, _default_val) -> {
      // Defaulted works like Optional for validation - value can be present or absent
      // If present, validate it matches the inner type
      case decode.run(value, decode.optional(decode.dynamic)) {
        Ok(option.Some(inner_val)) ->
          validate_value_type(inner_val, inner_type, type_key_identifier)
        Ok(option.None) -> Ok(value)
        Error(err) ->
          Error(
            ParserJsonParserError(format_decode_error_message(
              err,
              option.Some(type_key_identifier),
            )),
          )
      }
    }
  }
}

fn validate_value_type_helper(
  value: Dynamic,
  decoder: decode.Decoder(a),
  type_key_identifier: String,
) {
  case decode.run(value, decoder) {
    Ok(_) -> Ok(value)
    Error(err) ->
      Error(
        ParserJsonParserError(format_decode_error_message(
          err,
          option.Some(type_key_identifier),
        )),
      )
  }
}

/// Validates that inputs match the expected params in both keys and types.
/// Returns an error if there are missing keys, extra keys, or type mismatches.
/// Note: Optional and Defaulted params are allowed to be omitted from inputs.
pub fn inputs_validator(
  params params: Dict(String, AcceptedTypes),
  inputs inputs: Dict(String, Dynamic),
) -> Result(Bool, String) {
  // Filter out optional and defaulted params - they're not required
  let required_params =
    params
    |> dict.filter(fn(_, typ) {
      case typ {
        helpers.Optional(_) -> False
        helpers.Defaulted(_, _) -> False
        _ -> True
      }
    })

  let required_param_keys = required_params |> dict.keys |> set.from_list
  let param_keys = params |> dict.keys |> set.from_list
  let input_keys = inputs |> dict.keys |> set.from_list

  // Only required params must be present
  let missing_required_keys =
    set.difference(required_param_keys, input_keys) |> set.to_list
  // Inputs must only contain keys that exist in params (required or optional)
  let keys_only_in_inputs =
    set.difference(input_keys, param_keys) |> set.to_list

  // see if we have the same inputs and params
  use _ <- result.try(case missing_required_keys, keys_only_in_inputs {
    [], [] -> Ok(True)
    _, [] ->
      Error(
        "Missing keys in input: "
        <> { missing_required_keys |> string.join(", ") },
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
        <> { missing_required_keys |> string.join(", ") },
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

/// Validates that all items in a list have unique values for a given property.
/// Returns a ParserDuplicateError listing any duplicate values found.
pub fn validate_relevant_uniqueness(
  things_to_validate_uniqueness_for: List(a),
  fetch_property: fn(a) -> String,
  thing_label: String,
) -> Result(Bool, CompilationError) {
  let dupe_names =
    things_to_validate_uniqueness_for
    |> list.group(fn(thing) { fetch_property(thing) })
    |> dict.filter(fn(_, occurrences) { list.length(occurrences) > 1 })
    |> dict.keys

  case dupe_names {
    [] -> Ok(True)
    _ ->
      Error(ParserDuplicateError(
        "Duplicate "
        <> thing_label
        <> ": "
        <> { dupe_names |> string.join(", ") },
      ))
  }
}

/// Validates inputs against params for a collection of paired items.
/// Aggregates all validation errors across the collection into a single result.
pub fn validate_inputs_for_collection(
  input_param_collections: List(#(a, b)),
  get_inputs: fn(a) -> Dict(String, Dynamic),
  get_params: fn(b) -> Dict(String, AcceptedTypes),
) -> Result(Bool, CompilationError) {
  let errors =
    input_param_collections
    |> list.filter_map(fn(collection) {
      let #(input_collection, param_collection) = collection
      case
        inputs_validator(
          params: get_params(param_collection),
          inputs: get_inputs(input_collection),
        )
      {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  case errors {
    "" -> Ok(True)
    _ -> Error(ParserJsonParserError("Input validation errors: " <> errors))
  }
}

/// Checks if any keys in the referrer collection overlap with the reference collection.
/// Returns an error with the overlapping keys if overshadowing is detected.
pub fn check_collection_key_overshadowing(
  reference_collection: Dict(String, a),
  referrer_collection: Dict(String, b),
  error_msg: String,
) -> Result(Bool, String) {
  let reference_names = reference_collection |> dict.keys |> set.from_list
  let referrer_names = referrer_collection |> dict.keys |> set.from_list
  let overshadowing_params = {
    set.intersection(reference_names, referrer_names) |> set.to_list
  }

  case overshadowing_params {
    [] -> Ok(True)
    _ -> Error(error_msg <> overshadowing_params |> string.join(", "))
  }
}
