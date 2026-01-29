import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/modifier_types
import caffeine_lang/common/refinement_types
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string

/// Validates that a dynamic value matches the expected AcceptedType.
/// Returns the original value if valid, or a CompilationError describing the type mismatch.
@internal
pub fn validate_value_type(
  value: Dynamic,
  expected_type: AcceptedTypes,
  type_key_identifier: String,
) -> Result(Dynamic, CompilationError) {
  accepted_types.validate_value(expected_type, value)
  |> result.map_error(fn(err) {
    errors.ParserJsonParserError(errors.format_decode_error_message(
      err,
      option.Some(type_key_identifier),
    ))
  })
}

/// Validates that inputs match the expected params in both keys and types.
/// Returns an error if there are missing keys, extra keys, or type mismatches.
/// Note: Optional and Defaulted params are allowed to be omitted from inputs.
@internal
pub fn inputs_validator(
  params params: Dict(String, AcceptedTypes),
  inputs inputs: Dict(String, Dynamic),
  missing_inputs_ok missing_inputs_ok: Bool,
) -> Result(Bool, String) {
  // Filter out optional and defaulted params - they're not required
  let required_params =
    params
    |> dict.filter(fn(_, typ) { !is_optional_or_defaulted(typ) })

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
      [], [], _ -> Ok(True)
      _, [], True -> Ok(True)
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
    |> list.map(fn(err) { err.msg })
    |> string.join(", ")

  case type_validation_errors {
    "" -> Ok(True)
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
) -> Result(Bool, CompilationError) {
  let dupe_names =
    items
    |> list.group(fn(thing) { fetch_property(thing) })
    |> dict.filter(fn(_, occurrences) { list.length(occurrences) > 1 })
    |> dict.keys

  case dupe_names {
    [] -> Ok(True)
    _ ->
      Error(errors.ParserDuplicateError(
        "Duplicate "
        <> thing_label
        <> ": "
        <> { dupe_names |> string.join(", ") },
      ))
  }
}

/// Validates inputs against params for a collection of paired items.
/// Aggregates all validation errors across the collection into a single result.
@internal
pub fn validate_inputs_for_collection(
  input_param_collections input_param_collections: List(#(a, b)),
  get_inputs get_inputs: fn(a) -> Dict(String, Dynamic),
  get_params get_params: fn(b) -> Dict(String, AcceptedTypes),
  with get_identifier: fn(a) -> String,
  missing_inputs_ok missing_inputs_ok: Bool,
) -> Result(Bool, CompilationError) {
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
        Error(msg) ->
          Ok(get_identifier(input_collection) <> " - " <> msg)
      }
    })
    |> string.join(", ")

  case validation_errors {
    "" -> Ok(True)
    _ ->
      Error(errors.ParserJsonParserError(
        "Input validation errors: " <> validation_errors,
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

/// Checks if a type is optional or has a default value.
/// This includes:
/// - ModifierType(Optional(_))
/// - ModifierType(Defaulted(_, _))
/// - RefinementType(OneOf(ModifierType(Optional(_)), _))
/// - RefinementType(OneOf(ModifierType(Defaulted(_, _)), _))
fn is_optional_or_defaulted(typ: AcceptedTypes) -> Bool {
  case typ {
    accepted_types.ModifierType(modifier_types.Optional(_)) -> True
    accepted_types.ModifierType(modifier_types.Defaulted(_, _)) -> True
    accepted_types.RefinementType(refinement_types.OneOf(inner, _)) ->
      is_optional_or_defaulted(inner)
    _ -> False
  }
}
