import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lang/value.{type Value}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string

/// Validates that a Value matches the expected AcceptedType.
/// Returns the original value if valid, or a CompilationError describing the type mismatch.
@internal
pub fn validate_value_type(
  val: Value,
  expected_type: AcceptedTypes,
  type_key_identifier: String,
) -> Result(Value, CompilationError) {
  types.validate_value(expected_type, val)
  |> result.map_error(fn(err) {
    errors.ParserJsonParserError(
      msg: errors.format_validation_error_message(
        err,
        option.Some(type_key_identifier),
        option.Some(val),
      ),
      context: errors.empty_context(),
    )
  })
}

/// Validates that inputs match the expected params in both keys and types.
/// Returns an error if there are missing keys, extra keys, or type mismatches.
/// Note: Optional and Defaulted params are allowed to be omitted from inputs.
@internal
pub fn inputs_validator(
  params params: Dict(String, AcceptedTypes),
  inputs inputs: Dict(String, Value),
  missing_inputs_ok missing_inputs_ok: Bool,
) -> Result(Nil, String) {
  // Filter out optional and defaulted params - they're not required
  let required_params =
    params
    |> dict.filter(fn(_, typ) { !types.is_optional_or_defaulted(typ) })

  let required_param_keys = required_params |> dict.keys |> set.from_list
  let param_keys = params |> dict.keys |> set.from_list
  let input_keys = inputs |> dict.keys |> set.from_list

  // Only required params must be present
  let missing_required_keys =
    set.difference(required_param_keys, input_keys) |> set.to_list
  // Inputs must only contain keys that exist in params (required or optional)
  let keys_only_in_inputs =
    set.difference(input_keys, param_keys) |> set.to_list

  // see if we have the same inputs and params. Extra keys are always rejected;
  // missing keys only rejected when missing_inputs_ok is False
  use _ <- result.try(
    case missing_required_keys, keys_only_in_inputs, missing_inputs_ok {
      [], [], _ -> Ok(Nil)
      _, [], True -> Ok(Nil)
      _, [], False ->
        Error(
          "Missing keys in input: "
          <> { missing_required_keys |> string.join(", ") },
        )
      [], _, _ ->
        Error(
          "Extra keys in input: "
          <> { keys_only_in_inputs |> string.join(", ") },
        )
      _, _, True ->
        Error(
          "Extra keys in input: "
          <> { keys_only_in_inputs |> string.join(", ") },
        )
      _, _, False ->
        Error(
          "Extra keys in input: "
          <> { keys_only_in_inputs |> string.join(", ") }
          <> " and missing keys in input: "
          <> { missing_required_keys |> string.join(", ") },
        )
    },
  )

  let type_validation_errors =
    inputs
    |> dict.to_list
    |> list.filter_map(fn(pair) {
      let #(key, value) = pair
      // only validate types for keys that exist in params (extra keys handled above)
      case params |> dict.get(key) {
        Error(Nil) -> Error(Nil)
        Ok(expected_type) ->
          case validate_value_type(value, expected_type, key) {
            Ok(_) -> Error(Nil)
            Error(errs) -> Ok(errs)
          }
      }
    })
    |> list.map(errors.to_message)
    |> string.join(", ")

  case type_validation_errors {
    "" -> Ok(Nil)
    _ -> Error(type_validation_errors)
  }
}

/// Validates that all items in a list have unique values for a given property.
/// Returns a ParserDuplicateError listing any duplicate values found.
@internal
pub fn validate_relevant_uniqueness(
  items: List(a),
  by fetch_property: fn(a) -> String,
  label thing_label: String,
) -> Result(Nil, CompilationError) {
  let dupe_names =
    items
    |> list.group(fn(thing) { fetch_property(thing) })
    |> dict.filter(fn(_, occurrences) { list.length(occurrences) > 1 })
    |> dict.keys

  case dupe_names {
    [] -> Ok(Nil)
    _ ->
      Error(errors.ParserDuplicateError(
        msg: "Duplicate "
          <> thing_label
          <> ": "
          <> { dupe_names |> string.join(", ") },
        context: errors.empty_context(),
      ))
  }
}

/// Validates inputs against params for a collection of paired items.
/// Aggregates all validation errors across the collection into a single result.
@internal
pub fn validate_inputs_for_collection(
  input_param_collections input_param_collections: List(#(a, b)),
  get_inputs get_inputs: fn(a) -> Dict(String, Value),
  get_params get_params: fn(b) -> Dict(String, AcceptedTypes),
  with get_identifier: fn(a) -> String,
  missing_inputs_ok missing_inputs_ok: Bool,
) -> Result(Nil, CompilationError) {
  let validation_errors =
    input_param_collections
    |> list.filter_map(fn(collection) {
      let #(input_collection, param_collection) = collection
      case
        inputs_validator(
          params: get_params(param_collection),
          inputs: get_inputs(input_collection),
          missing_inputs_ok: missing_inputs_ok,
        )
      {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(get_identifier(input_collection) <> " - " <> msg)
      }
    })
    |> string.join(", ")

  case validation_errors {
    "" -> Ok(Nil)
    _ ->
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: " <> validation_errors,
        context: errors.empty_context(),
      ))
  }
}

/// Validates that no items in a collection have overshadowing keys.
/// Applies `check_collection_key_overshadowing` to each pair and aggregates errors.
@internal
pub fn validate_no_overshadowing(
  items: List(#(a, b)),
  get_check_collection get_check_collection: fn(a) -> Dict(String, c),
  get_against_collection get_against_collection: fn(b) -> Dict(String, d),
  get_error_label get_error_label: fn(a) -> String,
) -> Result(Nil, CompilationError) {
  let overshadow_errors =
    items
    |> list.filter_map(fn(pair) {
      let #(item, against) = pair
      case
        check_collection_key_overshadowing(
          in: get_check_collection(item),
          against: get_against_collection(against),
          with: get_error_label(item),
        )
      {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  case overshadow_errors {
    "" -> Ok(Nil)
    _ ->
      Error(errors.ParserDuplicateError(
        msg: overshadow_errors,
        context: errors.empty_context(),
      ))
  }
}

/// Checks if any keys in the referrer collection overlap with the reference collection.
/// Returns an error with the overlapping keys if overshadowing is detected.
@internal
pub fn check_collection_key_overshadowing(
  in reference_collection: Dict(String, a),
  against referrer_collection: Dict(String, b),
  with error_msg: String,
) -> Result(Nil, String) {
  let reference_names = reference_collection |> dict.keys |> set.from_list
  let referrer_names = referrer_collection |> dict.keys |> set.from_list
  let overshadowing_params = {
    set.intersection(reference_names, referrer_names) |> set.to_list
  }

  case overshadowing_params {
    [] -> Ok(Nil)
    _ -> Error(error_msg <> overshadowing_params |> string.join(", "))
  }
}
