import caffeine_lang/analysis/vendor
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/identifiers
import caffeine_lang/linker/blueprints.{type Blueprint, type BlueprintValidated}
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/linker/ir
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

/// Returns the hardcoded set of reserved labels.
/// Reserved labels are param keys consumed into structured fields that should
/// not appear in misc metadata tags. The "vendor" param is excluded because
/// it is intentionally surfaced as a tag.
@internal
pub fn reserved_labels() -> Set(String) {
  // SLO params + Dependency params
  [
    "threshold", "window_in_days", "indicators", "evaluation", "vendor", "tags",
    "runbook", "relations",
  ]
  |> set.from_list
  |> set.delete("vendor")
}

/// Build intermediate representations from validated expectations across multiple files.
@internal
pub fn build_all(
  expectations_with_paths: List(
    #(List(#(Expectation, Blueprint(BlueprintValidated))), String),
  ),
) -> Result(List(ir.IntermediateRepresentation(ir.Linked)), CompilationError) {
  let reserved = reserved_labels()
  expectations_with_paths
  |> list.map(fn(pair) {
    let #(expectations_blueprint_collection, file_path) = pair
    build(expectations_blueprint_collection, file_path, reserved)
  })
  |> errors.from_results()
  |> result.map(list.flatten)
}

/// Build intermediate representations from validated expectations for a single file.
fn build(
  expectations_blueprint_collection: List(
    #(Expectation, Blueprint(BlueprintValidated)),
  ),
  file_path: String,
  reserved_labels: Set(String),
) -> Result(List(ir.IntermediateRepresentation(ir.Linked)), CompilationError) {
  let #(org, team, service) = helpers.extract_path_prefix(file_path)

  expectations_blueprint_collection
  |> list.try_map(fn(expectation_and_blueprint_pair) {
    let #(expectation, blueprint) = expectation_and_blueprint_pair

    // Merge blueprint inputs with expectation inputs.
    // Expectation inputs override blueprint inputs for the same key.
    let merged_inputs = dict.merge(blueprint.inputs, expectation.inputs)

    let value_tuples = build_value_tuples(merged_inputs, blueprint.params)
    let misc_metadata = extract_misc_metadata(value_tuples, reserved_labels)
    let unique_name = org <> "_" <> service <> "_" <> expectation.name

    // Detect SLO and dependency fields from value tuples.
    let slo_fields = detect_slo_fields(value_tuples)
    let dependency_fields = detect_dependency_fields(value_tuples)
    let has_slo = option.is_some(slo_fields)

    // Resolve vendor from value tuples: required for SLO, None for dependency-only.
    use resolved_vendor <- result.try(resolve_vendor_from_values(
      value_tuples,
      has_slo:,
      identifier: org
        <> "."
        <> team
        <> "."
        <> service
        <> "."
        <> expectation.name,
    ))

    Ok(ir.IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel(expectation.name),
        org_name: identifiers.OrgName(org),
        service_name: identifiers.ServiceName(service),
        blueprint_name: identifiers.BlueprintName(blueprint.name),
        team_name: identifiers.TeamName(team),
        misc: misc_metadata,
      ),
      unique_identifier: unique_name,
      values: value_tuples,
      slo_fields: slo_fields,
      dependency_fields: dependency_fields,
      vendor: resolved_vendor,
    ))
  })
}

/// Detect SLO fields from value tuples.
/// Returns Some(SloFields) if SLO-related params are present, None otherwise.
fn detect_slo_fields(
  value_tuples: List(helpers.ValueTuple),
) -> option.Option(ir.SloFields) {
  let has_slo_params =
    list.any(value_tuples, fn(vt) {
      vt.label == "threshold"
      || vt.label == "evaluation"
      || vt.label == "indicators"
    })

  case has_slo_params {
    True -> option.Some(build_slo_fields(value_tuples))
    False -> option.None
  }
}

/// Detect dependency fields from value tuples.
/// Returns Some(DependencyFields) if relations param is present, None otherwise.
fn detect_dependency_fields(
  value_tuples: List(helpers.ValueTuple),
) -> option.Option(ir.DependencyFields) {
  let has_relations = list.any(value_tuples, fn(vt) { vt.label == "relations" })

  case has_relations {
    True -> option.Some(build_dependency_fields(value_tuples))
    False -> option.None
  }
}

/// Resolves the vendor from value tuples at IR construction time.
/// SLO artifacts require a vendor; dependency-only artifacts get None.
fn resolve_vendor_from_values(
  value_tuples: List(helpers.ValueTuple),
  has_slo has_slo: Bool,
  identifier identifier: String,
) -> Result(option.Option(vendor.Vendor), CompilationError) {
  use <- bool.guard(when: !has_slo, return: Ok(option.None))

  let vendor_value =
    value_tuples
    |> list.find(fn(vt) { vt.label == "vendor" })

  case vendor_value {
    Error(Nil) ->
      Error(errors.linker_vendor_resolution_error(
        msg: "expectation '" <> identifier <> "' - missing 'vendor' field",
      ))
    Ok(vt) ->
      case value.extract_string(vt.value) {
        Error(_) ->
          Error(errors.linker_vendor_resolution_error(
            msg: "expectation '"
            <> identifier
            <> "' - 'vendor' field is not a string",
          ))
        Ok(vendor_string) ->
          case vendor.resolve_vendor(vendor_string) {
            Ok(v) -> Ok(option.Some(v))
            Error(_) ->
              Error(errors.linker_vendor_resolution_error(
                msg: "expectation '"
                <> identifier
                <> "' - unknown vendor '"
                <> vendor_string
                <> "'",
              ))
          }
      }
  }
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

/// Extract SLO-specific fields from value tuples.
fn build_slo_fields(value_tuples: List(helpers.ValueTuple)) -> ir.SloFields {
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

  ir.SloFields(
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
) -> ir.DependencyFields {
  ir.DependencyFields(
    relations: helpers.extract_relations(value_tuples),
    tags: helpers.extract_tags(value_tuples),
  )
}
