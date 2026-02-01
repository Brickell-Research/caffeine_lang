import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/helpers
import caffeine_lang/common/modifier_types
import caffeine_lang/common/refinement_types
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations.{type Expectation}
import gleam/bool
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option

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
  helpers.extract_path_prefix(path)
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
    use <- bool.guard(
      when: dict.has_key(merged_inputs, label),
      return: Error(Nil),
    )
    case accepted_types.is_optional_or_defaulted(typ) {
      True -> Ok(helpers.ValueTuple(label:, typ:, value: dynamic.nil()))
      False -> Error(Nil)
    }
  })
}

/// Extract misc metadata from value tuples.
/// Filters out reserved labels and unsupported types.
/// Each key maps to a list of string values (primitives become single-element
/// lists, collection lists are exploded, nulls are excluded).
fn extract_misc_metadata(
  value_tuples: List(helpers.ValueTuple),
) -> dict.Dict(String, List(String)) {
  value_tuples
  |> list.filter_map(fn(value_tuple) {
    // Skip reserved labels
    case value_tuple.label {
      // TODO: Make the tag filtering dynamic.
      "window_in_days" | "threshold" | "evaluation" | "tags" | "runbook" ->
        Error(Nil)
      _ -> {
        case resolve_values_for_tag(value_tuple.typ, value_tuple.value) {
          Ok([]) -> Error(Nil)
          Ok(values) -> Ok(#(value_tuple.label, values))
          Error(_) -> Error(Nil)
        }
      }
    }
  })
  |> dict.from_list
}

/// Resolves a value tuple to a list of strings for use as tags.
/// Primitives and refinements produce a single-element list.
/// Lists are exploded into multiple string values.
/// Dicts and type alias refs are unsupported.
/// Optional(None) produces an empty list (filtered out).
/// Defaulted(None) produces the default value.
fn resolve_values_for_tag(
  typ: accepted_types.AcceptedTypes,
  value: dynamic.Dynamic,
) -> Result(List(String), Nil) {
  case typ {
    accepted_types.PrimitiveType(_) -> {
      case decode.run(value, accepted_types.decode_value_to_string(typ)) {
        Ok(s) -> Ok([s])
        Error(_) -> Error(Nil)
      }
    }
    accepted_types.RefinementType(refinement) -> {
      case refinement {
        refinement_types.OneOf(inner, _) -> resolve_values_for_tag(inner, value)
        refinement_types.InclusiveRange(inner, _, _) ->
          resolve_values_for_tag(inner, value)
      }
    }
    accepted_types.CollectionType(collection_types.List(inner)) -> {
      case
        decode.run(value, accepted_types.decode_list_values_to_strings(inner))
      {
        Ok(strings) -> Ok(strings)
        Error(_) -> Error(Nil)
      }
    }
    accepted_types.CollectionType(collection_types.Dict(_, _)) -> Error(Nil)
    accepted_types.ModifierType(modifier_types.Optional(inner)) -> {
      case decode.run(value, decode.optional(decode.dynamic)) {
        Ok(option.Some(inner_val)) -> resolve_values_for_tag(inner, inner_val)
        Ok(option.None) -> Ok([])
        Error(_) -> Ok([])
      }
    }
    accepted_types.ModifierType(modifier_types.Defaulted(inner, default)) -> {
      case decode.run(value, decode.optional(decode.dynamic)) {
        Ok(option.Some(inner_val)) -> resolve_values_for_tag(inner, inner_val)
        Ok(option.None) -> Ok([default])
        Error(_) -> Ok([default])
      }
    }
    accepted_types.TypeAliasRef(_) -> Error(Nil)
  }
}
