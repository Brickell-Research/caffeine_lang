import caffeine_lang/analysis/semantic_analyzer.{type IntermediateRepresentation}
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{DependencyRelations, SLO}
import caffeine_lang/linker/blueprints.{type Blueprint}
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/types.{
  type AcceptedTypes, CollectionType, Defaulted, Dict, InclusiveRange,
  List as ListType, ModifierType, OneOf, Optional, PrimitiveType, RecordType,
  RefinementType,
}
import caffeine_lang/value
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option
import gleam/result

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

/// Build intermediate representations from validated expectations for a single file.
fn build(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
  file_path: String,
) -> List(IntermediateRepresentation) {
  let #(org, team, service) = helpers.extract_path_prefix(file_path)

  expectations_blueprint_collection
  |> list.map(fn(expectation_and_blueprint_pair) {
    let #(expectation, blueprint) = expectation_and_blueprint_pair

    // Merge blueprint inputs with expectation inputs.
    // Expectation inputs override blueprint inputs for the same key.
    let merged_inputs = dict.merge(blueprint.inputs, expectation.inputs)

    let value_tuples = build_value_tuples(merged_inputs, blueprint.params)
    let misc_metadata = extract_misc_metadata(value_tuples)
    let unique_name = org <> "_" <> service <> "_" <> expectation.name
    let artifact_data =
      build_artifact_data(blueprint.artifact_refs, value_tuples)

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
      artifact_data: artifact_data,
      vendor: semantic_analyzer.NoVendor,
    )
  })
}

/// Build value tuples from merged inputs and params.
/// Includes both provided inputs and unprovided Optional/Defaulted params.
fn build_value_tuples(
  merged_inputs: dict.Dict(String, value.Value),
  params: dict.Dict(String, AcceptedTypes),
) -> List(helpers.ValueTuple) {
  let provided = build_provided_value_tuples(merged_inputs, params)
  let unprovided = build_unprovided_optional_value_tuples(merged_inputs, params)
  list.append(provided, unprovided)
}

/// Build value tuples from provided inputs.
fn build_provided_value_tuples(
  merged_inputs: dict.Dict(String, value.Value),
  params: dict.Dict(String, AcceptedTypes),
) -> List(helpers.ValueTuple) {
  merged_inputs
  |> dict.to_list
  |> list.filter_map(fn(pair) {
    let #(label, val) = pair
    case dict.get(params, label) {
      Ok(typ) -> Ok(helpers.ValueTuple(label:, typ:, value: val))
      Error(Nil) -> Error(Nil)
    }
  })
}

/// Build value tuples for Optional/Defaulted params that weren't provided.
/// These need to be in value_tuples so the templatizer can resolve them.
fn build_unprovided_optional_value_tuples(
  merged_inputs: dict.Dict(String, value.Value),
  params: dict.Dict(String, AcceptedTypes),
) -> List(helpers.ValueTuple) {
  params
  |> dict.to_list
  |> list.filter_map(fn(param) {
    let #(label, typ) = param
    use <- bool.guard(
      when: dict.has_key(merged_inputs, label),
      return: Error(Nil),
    )
    case types.is_optional_or_defaulted(typ) {
      True -> Ok(helpers.ValueTuple(label:, typ:, value: value.NilValue))
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
  typ: AcceptedTypes,
  val: value.Value,
) -> Result(List(String), Nil) {
  case typ {
    PrimitiveType(_) -> Ok([value.to_string(val)])
    RefinementType(refinement) -> {
      case refinement {
        OneOf(inner, _) -> resolve_values_for_tag(inner, val)
        InclusiveRange(inner, _, _) -> resolve_values_for_tag(inner, val)
      }
    }
    CollectionType(ListType(inner)) -> {
      case val {
        value.ListValue(items) ->
          items
          |> list.try_map(fn(item) {
            resolve_values_for_tag(inner, item)
            |> result.map(fn(strings) { strings })
          })
          |> result.map(list.flatten)
        _ -> Error(Nil)
      }
    }
    CollectionType(Dict(_, _)) -> Error(Nil)
    RecordType(_) -> Error(Nil)
    ModifierType(Optional(inner)) -> {
      case val {
        value.NilValue -> Ok([])
        _ -> resolve_values_for_tag(inner, val)
      }
    }
    ModifierType(Defaulted(inner, default)) -> {
      case val {
        value.NilValue -> Ok([default])
        _ -> resolve_values_for_tag(inner, val)
      }
    }
  }
}

/// Build structured artifact data from artifact refs and value tuples.
fn build_artifact_data(
  artifact_refs: List(artifacts.ArtifactType),
  value_tuples: List(helpers.ValueTuple),
) -> semantic_analyzer.ArtifactData {
  let has_slo = list.contains(artifact_refs, SLO)
  let has_deps = list.contains(artifact_refs, DependencyRelations)
  case has_slo, has_deps {
    True, True ->
      semantic_analyzer.SloWithDependency(
        slo: build_slo_fields(value_tuples),
        dependency: build_dependency_fields(value_tuples),
      )
    True, False -> semantic_analyzer.SloOnly(build_slo_fields(value_tuples))
    False, True ->
      semantic_analyzer.DependencyOnly(build_dependency_fields(value_tuples))
    // Fallback: treat as SLO-only (shouldn't happen with valid artifacts).
    False, False -> semantic_analyzer.SloOnly(build_slo_fields(value_tuples))
  }
}

/// Extract SLO-specific fields from value tuples.
fn build_slo_fields(
  value_tuples: List(helpers.ValueTuple),
) -> semantic_analyzer.SloFields {
  let threshold = helpers.extract_threshold(value_tuples)
  let indicators = helpers.extract_indicators(value_tuples)
  let window_in_days = helpers.extract_window_in_days(value_tuples)
  let evaluation =
    helpers.extract_value(value_tuples, "evaluation", value.extract_string)
    |> option.from_result
  let tags = helpers.extract_tags(value_tuples)
  let runbook =
    helpers.extract_value(value_tuples, "runbook", fn(v) {
      case v {
        value.NilValue -> Ok(option.None)
        value.StringValue(s) -> Ok(option.Some(s))
        _ -> Error(Nil)
      }
    })
    |> result.unwrap(option.None)

  semantic_analyzer.SloFields(
    threshold: threshold,
    indicators: indicators,
    window_in_days: window_in_days,
    evaluation: evaluation,
    tags: tags,
    runbook: runbook,
  )
}

/// Extract dependency-specific fields from value tuples.
fn build_dependency_fields(
  value_tuples: List(helpers.ValueTuple),
) -> semantic_analyzer.DependencyFields {
  semantic_analyzer.DependencyFields(
    relations: helpers.extract_relations(value_tuples),
    tags: helpers.extract_tags(value_tuples),
  )
}
