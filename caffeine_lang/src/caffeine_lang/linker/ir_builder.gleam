import caffeine_lang/analysis/vendor.{type Vendor}
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/identifiers
import caffeine_lang/linker/artifacts.{type ParamInfo}
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/linker/ir
import caffeine_lang/linker/measurements.{
  type Measurement, type MeasurementValidated,
}
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
import gleam/set.{type Set}

/// Derives the set of reserved labels from SLO params.
/// Reserved labels are param keys that are consumed into structured
/// fields and should not appear in misc metadata tags.
@internal
pub fn reserved_labels(params: dict.Dict(String, ParamInfo)) -> Set(String) {
  params
  |> dict.keys
  |> set.from_list
}

/// Build intermediate representations from validated expectations across multiple files.
@internal
pub fn build_all(
  expectations_with_paths: List(
    #(
      List(#(Expectation, option.Option(Measurement(MeasurementValidated)))),
      String,
    ),
  ),
  reserved_labels reserved_labels: Set(String),
  vendor_lookup vendor_lookup: dict.Dict(String, Vendor),
  slo_params slo_params: dict.Dict(String, ParamInfo),
) -> Result(List(ir.IntermediateRepresentation(ir.Linked)), CompilationError) {
  let unmeasured_params = build_unmeasured_param_types(slo_params)

  expectations_with_paths
  |> list.map(fn(pair) {
    let #(expectations_measurement_collection, file_path) = pair
    build(
      expectations_measurement_collection,
      file_path,
      reserved_labels,
      vendor_lookup,
      unmeasured_params,
    )
  })
  |> errors.from_results()
  |> result.map(list.flatten)
}

/// Build intermediate representations from validated expectations for a single file.
fn build(
  expectations_measurement_collection: List(
    #(Expectation, option.Option(Measurement(MeasurementValidated))),
  ),
  file_path: String,
  reserved_labels: Set(String),
  vendor_lookup: dict.Dict(String, Vendor),
  unmeasured_params: dict.Dict(String, AcceptedTypes),
) -> Result(List(ir.IntermediateRepresentation(ir.Linked)), CompilationError) {
  let #(org, team, service) = helpers.extract_path_prefix(file_path)

  expectations_measurement_collection
  |> list.try_map(fn(expectation_and_measurement_pair) {
    let #(expectation, maybe_measurement) = expectation_and_measurement_pair

    case maybe_measurement {
      option.Some(measurement) ->
        build_measured(
          expectation,
          measurement,
          org,
          team,
          service,
          reserved_labels,
          vendor_lookup,
        )
      option.None ->
        Ok(build_unmeasured(
          expectation,
          org,
          team,
          service,
          reserved_labels,
          unmeasured_params,
        ))
    }
  })
}

/// Build an IR from a measured expectation paired with its measurement.
fn build_measured(
  expectation: Expectation,
  measurement: Measurement(MeasurementValidated),
  org: String,
  team: String,
  service: String,
  reserved_labels: Set(String),
  vendor_lookup: dict.Dict(String, Vendor),
) -> Result(ir.IntermediateRepresentation(ir.Linked), CompilationError) {
  // Merge measurement inputs with expectation inputs.
  // Expectation inputs override measurement inputs for the same key.
  let merged_inputs = dict.merge(measurement.inputs, expectation.inputs)

  let value_tuples = build_value_tuples(merged_inputs, measurement.params)
  let index = helpers.index_value_tuples(value_tuples)
  let misc_metadata = extract_misc_metadata(value_tuples, reserved_labels)
  let unique_name = org <> "_" <> service <> "_" <> expectation.name
  let slo = build_slo_fields(index)

  // Resolve vendor from lookup.
  let resolved_vendor = case dict.get(vendor_lookup, measurement.name) {
    Ok(v) -> Ok(option.Some(v))
    Error(Nil) ->
      Error(errors.linker_vendor_resolution_error(
        msg: "expectation '"
        <> org
        <> "."
        <> team
        <> "."
        <> service
        <> "."
        <> expectation.name
        <> "' - measurement '"
        <> measurement.name
        <> "' has no associated vendor",
      ))
  }
  use resolved_vendor <- result.try(resolved_vendor)

  Ok(ir.IntermediateRepresentation(
    metadata: ir.IntermediateRepresentationMetaData(
      friendly_label: identifiers.ExpectationLabel(expectation.name),
      org_name: identifiers.OrgName(org),
      service_name: identifiers.ServiceName(service),
      measurement_name: identifiers.MeasurementName(measurement.name),
      team_name: identifiers.TeamName(team),
      misc: misc_metadata,
    ),
    unique_identifier: unique_name,
    values: value_tuples,
    slo: slo,
    vendor: resolved_vendor,
  ))
}

/// Build an IR from an unmeasured expectation.
/// Uses restricted params (threshold, window_in_days, depends_on) and sets vendor to None.
fn build_unmeasured(
  expectation: Expectation,
  org: String,
  team: String,
  service: String,
  reserved_labels: Set(String),
  unmeasured_params: dict.Dict(String, AcceptedTypes),
) -> ir.IntermediateRepresentation(ir.Linked) {
  let value_tuples =
    build_value_tuples(expectation.inputs, unmeasured_params)
  let index = helpers.index_value_tuples(value_tuples)
  let misc_metadata = extract_misc_metadata(value_tuples, reserved_labels)
  let unique_name = org <> "_" <> service <> "_" <> expectation.name
  let slo = build_slo_fields(index)

  ir.IntermediateRepresentation(
    metadata: ir.IntermediateRepresentationMetaData(
      friendly_label: identifiers.ExpectationLabel(expectation.name),
      org_name: identifiers.OrgName(org),
      service_name: identifiers.ServiceName(service),
      measurement_name: identifiers.MeasurementName("unmeasured"),
      team_name: identifiers.TeamName(team),
      misc: misc_metadata,
    ),
    unique_identifier: unique_name,
    values: value_tuples,
    slo: slo,
    vendor: option.None,
  )
}

/// Derives the restricted param types for unmeasured expectations from SLO params.
/// Only includes threshold, window_in_days, and depends_on.
fn build_unmeasured_param_types(
  slo_params: dict.Dict(String, ParamInfo),
) -> dict.Dict(String, AcceptedTypes) {
  let allowed = set.from_list(["threshold", "window_in_days", "depends_on"])
  slo_params
  |> dict.filter(fn(key, _) { set.contains(allowed, key) })
  |> artifacts.params_to_types()
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
/// Filters out reserved labels (derived from artifact params) and unsupported types.
/// Each key maps to a list of string values (primitives become single-element
/// lists, collection lists are exploded, nulls are excluded).
fn extract_misc_metadata(
  value_tuples: List(helpers.ValueTuple),
  reserved_labels: Set(String),
) -> dict.Dict(String, List(String)) {
  value_tuples
  |> list.filter_map(fn(value_tuple) {
    use <- bool.guard(
      when: set.contains(reserved_labels, value_tuple.label),
      return: Error(Nil),
    )
    case resolve_values_for_tag(value_tuple.typ, value_tuple.value) {
      Ok([]) -> Error(Nil)
      Ok(values) -> Ok(#(value_tuple.label, values))
      Error(_) -> Error(Nil)
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

/// Extract SLO-specific fields from an indexed Dict of ValueTuples.
/// Threshold defaults to the standard default when not present (e.g. unmeasured expectations).
fn build_slo_fields(
  index: dict.Dict(String, helpers.ValueTuple),
) -> ir.SloFields {
  let threshold =
    helpers.extract_value_indexed(index, "threshold", value.extract_percentage)
    |> result.unwrap(helpers.default_threshold_percentage)
  let indicators = helpers.extract_indicators_indexed(index)
  let window_in_days = helpers.extract_window_in_days_indexed(index)
  let evaluation =
    helpers.extract_value_indexed(index, "evaluation", value.extract_string)
    |> option.from_result
  let tags = helpers.extract_tags_indexed(index)
  let runbook =
    helpers.extract_value_indexed(index, "runbook", fn(v) {
      case v {
        value.NilValue -> Ok(option.None)
        value.StringValue(s) -> Ok(option.Some(s))
        _ -> Error(Nil)
      }
    })
    |> result.unwrap(option.None)
  let relations = helpers.extract_depends_on_indexed(index)
  let depends_on = case dict.is_empty(relations) {
    True -> option.None
    False -> option.Some(relations)
  }

  ir.SloFields(
    threshold: threshold,
    indicators: indicators,
    window_in_days: window_in_days,
    evaluation: evaluation,
    tags: tags,
    runbook: runbook,
    depends_on: depends_on,
  )
}
