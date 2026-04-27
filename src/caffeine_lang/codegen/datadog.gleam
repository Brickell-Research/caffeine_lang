import caffeine_lang/analysis/templatizer
import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts
import caffeine_lang/linker/ir.{
  type DepsValidated, type IntermediateRepresentation, type Resolved,
  IntermediateRepresentation, SloFields, ir_to_identifier,
}
import caffeine_lang/types.{
  CollectionType, Dict, PrimitiveType, String as StringType,
}
import caffeine_lang/value
import caffeine_lang/codegen/datadog_cql
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Resolves Datadog indicator templates in an intermediate representation.
@internal
pub fn resolve_indicators(
  ir: IntermediateRepresentation(DepsValidated),
) -> Result(IntermediateRepresentation(Resolved), CompilationError) {
  use indicators_value_tuple <- result.try(
    ir.values
    |> list.find(fn(vt) { vt.label == "indicators" })
    |> result.replace_error(errors.semantic_analysis_template_resolution_error(
      msg: "expectation '"
      <> ir_to_identifier(ir)
      <> "' - missing 'indicators' field in IR",
    )),
  )

  use indicators_dict <- result.try(
    value.extract_string_dict(indicators_value_tuple.value)
    |> result.map_error(fn(_) {
      errors.semantic_analysis_template_resolution_error(
        msg: "expectation '"
        <> ir_to_identifier(ir)
        <> "' - failed to decode indicators",
      )
    }),
  )

  let identifier = ir_to_identifier(ir)

  // Resolve all indicators and collect results.
  use resolved_indicators <- result.try(
    indicators_dict
    |> dict.to_list
    |> list.try_map(fn(pair) {
      let #(key, indicator) = pair
      use resolved <- result.map(templatizer.parse_and_resolve_query_template(
        indicator,
        ir.values,
        from: identifier,
      ))
      #(key, resolved)
    }),
  )

  // Build the new indicators dict as a Value.
  let resolved_indicators_value =
    resolved_indicators
    |> list.map(fn(pair) { #(pair.0, value.StringValue(pair.1)) })
    |> dict.from_list
    |> value.DictValue

  // Create the new indicators ValueTuple.
  let new_indicators_value_tuple =
    helpers.ValueTuple(
      "indicators",
      CollectionType(Dict(PrimitiveType(StringType), PrimitiveType(StringType))),
      resolved_indicators_value,
    )

  // Also resolve templates in the "evaluation" field if present.
  let evaluation_tuple_result =
    ir.values
    |> list.find(fn(vt) { vt.label == "evaluation" })

  use resolved_evaluation_tuple <- result.try(case evaluation_tuple_result {
    Error(_) -> Ok(option.None)
    Ok(evaluation_tuple) -> {
      use evaluation_string <- result.try(
        value.extract_string(evaluation_tuple.value)
        |> result.map_error(fn(_) {
          errors.semantic_analysis_template_resolution_error(
            msg: "expectation '"
            <> ir_to_identifier(ir)
            <> "' - failed to decode 'evaluation' field as string",
          )
        }),
      )
      templatizer.parse_and_resolve_query_template(
        evaluation_string,
        ir.values,
        from: identifier,
      )
      |> result.map(fn(resolved_evaluation) {
        option.Some(helpers.ValueTuple(
          "evaluation",
          PrimitiveType(StringType),
          value.StringValue(resolved_evaluation),
        ))
      })
    }
  })

  // Update the IR with the resolved indicators and evaluation.
  let new_values =
    ir.values
    |> list.map(fn(vt) {
      case vt.label {
        "indicators" -> new_indicators_value_tuple
        "evaluation" ->
          case resolved_evaluation_tuple {
            option.Some(new_evaluation) -> new_evaluation
            option.None -> vt
          }
        _ -> vt
      }
    })

  // Also update the structured slo fields with resolved values.
  let resolved_indicators_dict = resolved_indicators |> dict.from_list
  let resolved_eval = case resolved_evaluation_tuple {
    option.Some(vt) -> value.extract_string(vt.value) |> option.from_result
    option.None -> ir.slo.evaluation
  }
  let new_ir =
    ir.map_slo(IntermediateRepresentation(..ir, values: new_values), fn(slo) {
      SloFields(
        ..slo,
        indicators: resolved_indicators_dict,
        evaluation: resolved_eval,
      )
    })

  Ok(ir.promote(new_ir))
}

/// Default evaluation expression used when no explicit evaluation is provided.
const default_evaluation = "numerator / denominator"

/// Generate Terraform HCL from a list of Datadog IntermediateRepresentations.
/// Includes provider configuration and variables.
/// Note: Datadog does not use generator_utils.generate_terraform because it
/// returns warnings alongside the HCL string.
/// Generate only the Terraform resources for Datadog IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation(Resolved)),
) -> Result(#(List(terraform.Resource), List(String)), CompilationError) {
  irs
  |> list.try_fold(#([], []), fn(acc, ir) {
    let #(resources, warning_lists) = acc
    use #(resource, ir_warnings) <- result.try(ir_to_terraform_resource(ir))
    Ok(#([resource, ..resources], [ir_warnings, ..warning_lists]))
  })
  |> result.map(fn(pair) {
    #(list.reverse(pair.0), list.flatten(list.reverse(pair.1)))
  })
}

/// Convert a single IntermediateRepresentation to a Terraform Resource.
/// Uses CQL to parse the value expression and generate HCL blocks.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation(Resolved),
) -> Result(#(terraform.Resource, List(String)), CompilationError) {
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  let slo = ir.slo
  let threshold = slo.threshold
  let window_in_days = slo.window_in_days
  let indicators = slo.indicators
  let evaluation_expr = slo.evaluation |> option.unwrap(default_evaluation)
  let runbook = slo.runbook

  // Parse the evaluation expression using CQL and get HCL blocks.
  use datadog_cql.ResolvedSloHcl(slo_type, slo_blocks) <- result.try(
    datadog_cql.resolve_slo_to_hcl(evaluation_expr, indicators)
    |> result.map_error(fn(err) {
      errors.generator_slo_query_resolution_error(
        msg: "expectation '"
        <> ir_to_identifier(ir)
        <> "' - failed to resolve SLO query: "
        <> err,
      )
    }),
  )

  // Build dependency relation tags from SloFields.depends_on.
  let dependency_tags = case slo.depends_on {
    option.Some(relations) -> build_dependency_tags(relations)
    option.None -> []
  }

  // Build user-provided tags as key-value pairs.
  let user_tag_pairs = slo.tags

  // Build system tags from IR metadata.
  let system_tag_pairs =
    helpers.build_system_tag_pairs(
      org_name: ir.metadata.org_name,
      team_name: ir.metadata.team_name,
      service_name: ir.metadata.service_name,
      measurement_name: ir.metadata.measurement_name,
      friendly_label: ir.metadata.friendly_label,
      misc: ir.metadata.misc,
    )
    |> list.append(dependency_tags)

  // Detect overshadowing: user tags whose key matches a system tag key.
  let system_tag_keys =
    system_tag_pairs |> list.map(fn(pair) { pair.0 }) |> set.from_list

  let user_tag_keys =
    user_tag_pairs |> list.map(fn(pair) { pair.0 }) |> set.from_list

  let overlapping_keys = set.intersection(system_tag_keys, user_tag_keys)

  // Collect warnings about overshadowing and filter out overshadowed system tags.
  let #(final_system_tag_pairs, warnings) = case
    set.size(overlapping_keys) > 0
  {
    True -> {
      let warn_msgs =
        overlapping_keys
        |> set.to_list
        |> list.sort(string.compare)
        |> list.map(fn(key) {
          ir_to_identifier(ir)
          <> " - user tag '"
          <> key
          <> "' overshadows system tag"
        })
      let filtered =
        system_tag_pairs
        |> list.filter(fn(pair) { !set.contains(overlapping_keys, pair.0) })
      #(filtered, warn_msgs)
    }
    False -> #(system_tag_pairs, [])
  }

  let tags =
    list.append(final_system_tag_pairs, user_tag_pairs)
    |> list.map(fn(pair) { hcl.StringLiteral(pair.0 <> ":" <> pair.1) })
    |> hcl.ListExpr

  let identifier = ir_to_identifier(ir)

  use window_in_days_string <- result.try(
    window_to_timeframe(window_in_days)
    |> result.map_error(fn(err) { errors.prefix_error(err, identifier) }),
  )

  // Build the thresholds block (common to both types).
  let thresholds_block =
    hcl.simple_block("thresholds", [
      #("timeframe", hcl.StringLiteral(window_in_days_string)),
      #("target", hcl.FloatLiteral(threshold)),
    ])

  let type_str = case slo_type {
    datadog_cql.TimeSliceSlo -> "time_slice"
    datadog_cql.MetricSlo -> "metric"
  }

  let base_attributes = [
    #("name", hcl.StringLiteral(ir.metadata.friendly_label.value)),
    #("type", hcl.StringLiteral(type_str)),
    #("tags", tags),
  ]

  let attributes = case runbook {
    option.Some(url) -> [
      #("description", hcl.StringLiteral("[Runbook](" <> url <> ")")),
      ..base_attributes
    ]
    option.None -> base_attributes
  }

  Ok(#(
    terraform.Resource(
      type_: "datadog_service_level_objective",
      name: resource_name,
      attributes: dict.from_list(attributes),
      blocks: list.append(slo_blocks, [thresholds_block]),
      meta: hcl.empty_meta(),
      lifecycle: option.None,
    ),
    warnings,
  ))
}

/// Build dependency relation tag pairs from the relations dict.
/// Generates pairs like #("soft_dependency", "target1,target2").
fn build_dependency_tags(
  relations: dict.Dict(artifacts.DependencyRelationType, List(String)),
) -> List(#(String, String)) {
  relations
  |> dict.to_list
  |> list.sort(fn(a, b) {
    string.compare(
      artifacts.relation_type_to_string(a.0),
      artifacts.relation_type_to_string(b.0),
    )
  })
  |> list.map(fn(pair) {
    let #(relation_type, targets) = pair
    let sorted_targets = targets |> list.sort(string.compare)
    #(
      artifacts.relation_type_to_string(relation_type) <> "_dependency",
      string.join(sorted_targets, ","),
    )
  })
}

/// Convert window_in_days to Datadog timeframe string.
/// Range (1-90) is guaranteed by the standard library; Datadog further restricts to {7, 30, 90}.
@internal
pub fn window_to_timeframe(days: Int) -> Result(String, CompilationError) {
  let days_string = int.to_string(days)
  case days {
    7 | 30 | 90 -> Ok(days_string <> "d")
    _ ->
      Error(generator_utils.resolution_error(
        vendor: constants.vendor_datadog,
        msg: "Illegal window_in_days value: "
          <> days_string
          <> ". Accepted values are 7, 30, or 90.",
      ))
  }
}
