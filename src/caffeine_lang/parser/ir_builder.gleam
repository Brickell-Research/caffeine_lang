import caffeine_lang/common/accepted_types
import caffeine_lang/common/helpers
import caffeine_lang/common/modifier_types
import caffeine_lang/common/refinement_types
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations.{type Expectation}
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
import gleam/string

/// Build intermediate representations from validated expectations across multiple files.
@internal
pub fn build_all(
  expectations_with_paths: List(#(List(#(Expectation, Blueprint)), String)),
) -> List(IntermediateRepresentation) {
  expectations_with_paths
  |> list.map(fn(pair) {
    let #(expectations_blueprint_collection, file_path) = pair
    build(expectations_blueprint_collection, file_path)
  })
  |> list.flatten
}

/// Extract a meaningful prefix from the source path.
/// e.g., "examples/org/platform_team/authentication.caffeine" -> #("org", "platform_team", "authentication")
@internal
pub fn extract_path_prefix(path: String) -> #(String, String, String) {
  case
    path
    |> string.split("/")
    |> list.reverse
    |> list.take(3)
    |> list.reverse
    |> list.map(fn(segment) {
      // Remove file extension if present.
      case string.ends_with(segment, ".caffeine") {
        True -> string.drop_end(segment, 9)
        False ->
          case string.ends_with(segment, ".json") {
            True -> string.drop_end(segment, 5)
            False -> segment
          }
      }
    })
  {
    [org, team, service] -> #(org, team, service)
    // This is not actually a possible state, however for pattern matching completeness we
    // include it here.
    _ -> #("unknown", "unknown", "unknown")
  }
}

/// Build intermediate representations from validated expectations for a single file.
fn build(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
  file_path: String,
) -> List(IntermediateRepresentation) {
  let #(org, team, service) = extract_path_prefix(file_path)

  expectations_blueprint_collection
  |> list.map(fn(expectation_and_blueprint_pair) {
    let #(expectation, blueprint) = expectation_and_blueprint_pair

    // Merge blueprint inputs with expectation inputs.
    // Expectation inputs override blueprint inputs for the same key.
    let merged_inputs = dict.merge(blueprint.inputs, expectation.inputs)

    let value_tuples = build_value_tuples(merged_inputs, blueprint.params)
    let misc_metadata = extract_misc_metadata(value_tuples)
    let unique_name = org <> "_" <> service <> "_" <> expectation.name

    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: expectation.name,
        org_name: org,
        service_name: service,
        blueprint_name: blueprint.name,
        team_name: team,
        misc: misc_metadata,
      ),
      unique_identifier: unique_name,
      artifact_refs: blueprint.artifact_refs,
      values: value_tuples,
      vendor: option.None,
    )
  })
}

/// Build value tuples from merged inputs and params.
/// Includes both provided inputs and unprovided Optional/Defaulted params.
fn build_value_tuples(
  merged_inputs: dict.Dict(String, dynamic.Dynamic),
  params: dict.Dict(String, accepted_types.AcceptedTypes),
) -> List(helpers.ValueTuple) {
  let provided = build_provided_value_tuples(merged_inputs, params)
  let unprovided = build_unprovided_optional_value_tuples(merged_inputs, params)
  list.append(provided, unprovided)
}

/// Build value tuples from provided inputs.
fn build_provided_value_tuples(
  merged_inputs: dict.Dict(String, dynamic.Dynamic),
  params: dict.Dict(String, accepted_types.AcceptedTypes),
) -> List(helpers.ValueTuple) {
  merged_inputs
  |> dict.keys
  |> list.map(fn(label) {
    // Safe assertions since we've already validated everything.
    let assert Ok(value) = merged_inputs |> dict.get(label)
    let assert Ok(typ) = params |> dict.get(label)
    helpers.ValueTuple(label:, typ:, value:)
  })
}

/// Build value tuples for Optional/Defaulted params that weren't provided.
/// These need to be in value_tuples so the templatizer can resolve them.
fn build_unprovided_optional_value_tuples(
  merged_inputs: dict.Dict(String, dynamic.Dynamic),
  params: dict.Dict(String, accepted_types.AcceptedTypes),
) -> List(helpers.ValueTuple) {
  params
  |> dict.to_list
  |> list.filter_map(fn(param) {
    let #(label, typ) = param
    case dict.has_key(merged_inputs, label) {
      True -> Error(Nil)
      False ->
        case is_optional_or_defaulted(typ) {
          True -> Ok(helpers.ValueTuple(label:, typ:, value: dynamic.nil()))
          False -> Error(Nil)
        }
    }
  })
}

/// Checks if a type is optional or has a default value.
/// This includes:
/// - ModifierType(Optional(_))
/// - ModifierType(Defaulted(_, _))
/// - RefinementType(OneOf(ModifierType(Optional(_)), _))
/// - RefinementType(OneOf(ModifierType(Defaulted(_, _)), _))
fn is_optional_or_defaulted(typ: accepted_types.AcceptedTypes) -> Bool {
  case typ {
    accepted_types.ModifierType(modifier_types.Optional(_)) -> True
    accepted_types.ModifierType(modifier_types.Defaulted(_, _)) -> True
    accepted_types.RefinementType(refinement_types.OneOf(inner, _)) ->
      is_optional_or_defaulted(inner)
    _ -> False
  }
}

/// Extract misc metadata from value tuples.
/// Filters out non-string values and specific reserved labels.
/// Uses type-aware resolution to apply defaults from Defaulted types.
fn extract_misc_metadata(
  value_tuples: List(helpers.ValueTuple),
) -> dict.Dict(String, String) {
  value_tuples
  |> list.filter_map(fn(value_tuple) {
    // Skip reserved labels
    case value_tuple.label {
      // TODO: Make the tag filtering dynamic.
      "window_in_days" | "threshold" | "value" -> Error(Nil)
      _ -> {
        // Use type-aware resolution to handle defaults
        case resolve_value_for_tag(value_tuple) {
          Ok(value_string) -> Ok(#(value_tuple.label, value_string))
          Error(_) -> Error(Nil)
        }
      }
    }
  })
  |> dict.from_list
}

/// Resolves a value tuple to a string for use as a tag.
/// Handles Defaulted types by applying their default values when not provided.
fn resolve_value_for_tag(
  value_tuple: helpers.ValueTuple,
) -> Result(String, Nil) {
  // Identity function for string resolution (tags don't need template transformation)
  let identity = fn(s) { s }
  // For lists, join with comma (though tags typically don't use lists)
  let list_join = fn(items) { string.join(items, ",") }

  accepted_types.resolve_to_string(
    value_tuple.typ,
    value_tuple.value,
    identity,
    list_join,
  )
  |> result_to_nil_error
}

/// Convert Result(a, String) to Result(a, Nil)
fn result_to_nil_error(result: Result(a, String)) -> Result(a, Nil) {
  case result {
    Ok(val) -> Ok(val)
    Error(_) -> Error(Nil)
  }
}
