import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_lang/codegen/generator_utils
import caffeine_lang/common/constants
import caffeine_lang/common/errors.{
  type CompilationError, GeneratorDatadogTerraformResolutionError,
  GeneratorSloQueryResolutionError,
}
import caffeine_lang/common/helpers
import caffeine_lang/core/logger
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Generate Terraform HCL from a list of Datadog IntermediateRepresentations.
/// Includes provider configuration and variables.
pub fn generate_terraform(
  irs: List(IntermediateRepresentation),
) -> Result(String, CompilationError) {
  use resources <- result.try(generate_resources(irs))
  Ok(generator_utils.render_terraform_config(
    resources: resources,
    settings: terraform_settings(),
    providers: [provider()],
    variables: variables(),
  ))
}

/// Generate only the Terraform resources for Datadog IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(List(terraform.Resource), CompilationError) {
  irs |> list.try_map(ir_to_terraform_resource)
}

/// Terraform settings block with required Datadog provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        constants.vendor_datadog,
        terraform.ProviderRequirement("DataDog/datadog", option.Some("~> 3.0")),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// Datadog provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  terraform.Provider(
    name: constants.vendor_datadog,
    alias: option.None,
    attributes: dict.from_list([
      #("api_key", hcl.ref("var.datadog_api_key")),
      #("app_key", hcl.ref("var.datadog_app_key")),
    ]),
    blocks: [],
  )
}

/// Variables for Datadog API credentials.
@internal
pub fn variables() -> List(terraform.Variable) {
  [
    terraform.Variable(
      name: "datadog_api_key",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Datadog API key"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "datadog_app_key",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Datadog Application key"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
  ]
}

/// Convert a single IntermediateRepresentation to a Terraform Resource.
/// Uses CQL to parse the value expression and generate HCL blocks.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation,
) -> Result(terraform.Resource, CompilationError) {
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract values from IR.
  let threshold = helpers.extract_threshold(ir.values)
  let window_in_days = helpers.extract_window_in_days(ir.values)
  let indicators = helpers.extract_indicators(ir.values)
  let evaluation_expr =
    helpers.extract_value(ir.values, "evaluation", decode.string)
    |> result.unwrap("numerator / denominator")
  let runbook =
    helpers.extract_value(ir.values, "runbook", decode.optional(decode.string))
    |> result.unwrap(option.None)

  // Parse the evaluation expression using CQL and get HCL blocks.
  use cql_generator.ResolvedSloHcl(slo_type, slo_blocks) <- result.try(
    cql_generator.resolve_slo_to_hcl(evaluation_expr, indicators)
    |> result.map_error(fn(err) {
      GeneratorSloQueryResolutionError(
        msg: "expectation '"
        <> ir_to_identifier(ir)
        <> "' - failed to resolve SLO query: "
        <> err,
      )
    }),
  )

  // Build dependency relation tags if artifact refs include DependencyRelations.
  let dependency_tags = case
    ir.artifact_refs |> list.contains("DependencyRelations")
  {
    True -> build_dependency_tags(ir.values)
    False -> []
  }

  // Build user-provided tags as key-value pairs.
  let user_tag_pairs = helpers.extract_tags(ir.values)

  // Build system tags from IR metadata.
  let system_tag_pairs =
    helpers.build_system_tag_pairs(
      org_name: ir.metadata.org_name,
      team_name: ir.metadata.team_name,
      service_name: ir.metadata.service_name,
      blueprint_name: ir.metadata.blueprint_name,
      friendly_label: ir.metadata.friendly_label,
      artifact_refs: ir.artifact_refs,
      misc: ir.metadata.misc,
    )
    |> list.append(dependency_tags)

  // Detect overshadowing: user tags whose key matches a system tag key.
  let system_tag_keys =
    system_tag_pairs |> list.map(fn(pair) { pair.0 }) |> set.from_list

  let user_tag_keys =
    user_tag_pairs |> list.map(fn(pair) { pair.0 }) |> set.from_list

  let overlapping_keys = set.intersection(system_tag_keys, user_tag_keys)

  // Warn about overshadowing and filter out overshadowed system tags.
  let final_system_tag_pairs = case set.size(overlapping_keys) > 0 {
    True -> {
      overlapping_keys
      |> set.to_list
      |> list.sort(string.compare)
      |> list.each(fn(key) {
        logger.warn(
          ir_to_identifier(ir)
          <> " - user tag '"
          <> key
          <> "' overshadows system tag",
        )
      })
      system_tag_pairs
      |> list.filter(fn(pair) { !set.contains(overlapping_keys, pair.0) })
    }
    False -> system_tag_pairs
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
    cql_generator.TimeSliceSlo -> "time_slice"
    cql_generator.MetricSlo -> "metric"
  }

  let base_attributes = [
    #("name", hcl.StringLiteral(ir.metadata.friendly_label)),
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

  Ok(terraform.Resource(
    type_: "datadog_service_level_objective",
    name: resource_name,
    attributes: dict.from_list(attributes),
    blocks: list.append(slo_blocks, [thresholds_block]),
    meta: hcl.empty_meta(),
    lifecycle: option.None,
  ))
}

/// Build dependency relation tag pairs from the "relations" value.
/// Extracts the relations dict (maps relation type to list of targets) and generates
/// pairs like #("soft_dependency", "target1,target2").
fn build_dependency_tags(
  values: List(helpers.ValueTuple),
) -> List(#(String, String)) {
  helpers.extract_relations(values)
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) {
    let #(relation_type, targets) = pair
    let sorted_targets = targets |> list.sort(string.compare)
    #(relation_type <> "_dependency", string.join(sorted_targets, ","))
  })
}

/// Convert window_in_days to Datadog timeframe string.
@internal
pub fn window_to_timeframe(days: Int) -> Result(String, CompilationError) {
  let days_string = int.to_string(days)
  case days {
    7 | 30 | 90 -> Ok(days_string <> "d")
    // TODO: catch this earlier on in the compilation pipeline. Possible with RefinementTypes 😁
    _ ->
      Error(GeneratorDatadogTerraformResolutionError(
        msg: "Illegal window_in_days value: "
        <> days_string
        <> ". Accepted values are 7, 30, or 90.",
      ))
  }
}
