import caffeine_lang/common/constants
import caffeine_lang/common/errors.{
  type CompilationError, GeneratorDatadogTerraformResolutionError,
  GeneratorSloQueryResolutionError,
}
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import terra_madre/common
import terra_madre/hcl
import terra_madre/render
import terra_madre/terraform

/// Generate Terraform HCL from a list of Datadog IntermediateRepresentations.
/// Includes provider configuration and variables.
pub fn generate_terraform(
  irs: List(IntermediateRepresentation),
) -> Result(String, CompilationError) {
  use resources <- result.try(irs |> list.try_map(ir_to_terraform_resource))
  let config =
    terraform.Config(
      terraform: option.Some(terraform_settings()),
      providers: [provider()],
      resources: resources,
      data_sources: [],
      variables: variables(),
      outputs: [],
      locals: [],
      modules: [],
    )
  Ok(render.render_config(config))
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
  let threshold =
    helpers.extract_value(ir.values, "threshold", decode.float)
    |> result.unwrap(99.9)
  let window_in_days =
    helpers.extract_value(ir.values, "window_in_days", decode.int)
    |> result.unwrap(30)
  let queries =
    helpers.extract_value(
      ir.values,
      "queries",
      decode.dict(decode.string, decode.string),
    )
    |> result.unwrap(dict.new())
  let value_expr =
    helpers.extract_value(ir.values, "value", decode.string)
    |> result.unwrap("numerator / denominator")

  // Parse the value expression using CQL and get HCL blocks.
  use cql_generator.ResolvedSloHcl(slo_type, slo_blocks) <- result.try(
    cql_generator.resolve_slo_to_hcl(value_expr, queries)
    |> result.map_error(fn(err) {
      GeneratorSloQueryResolutionError(
        msg: "Failed to resolve SLO query for '"
        <> ir.metadata.friendly_label
        <> "': "
        <> err,
      )
    }),
  )

  // Build tags (common to both types).
  let tags =
    hcl.ListExpr(
      // Well known metadata info.
      [
        hcl.StringLiteral("managed_by:caffeine"),
        hcl.StringLiteral("caffeine_version:" <> constants.version),
        hcl.StringLiteral("org:" <> ir.metadata.org_name),
        hcl.StringLiteral("team:" <> ir.metadata.team_name),
        hcl.StringLiteral("service:" <> ir.metadata.service_name),
        hcl.StringLiteral("blueprint:" <> ir.metadata.blueprint_name),
        hcl.StringLiteral("expectation:" <> ir.metadata.friendly_label),
      ]
      |> list.append(
        // Generate artifact tags for each referenced artifact
        ir.artifact_refs
        |> list.map(fn(ref) { hcl.StringLiteral("artifact:" <> ref) }),
      )
      |> list.append(
        // Also add misc tags (sorted for deterministic output across targets).
        ir.metadata.misc
        |> dict.keys
        |> list.sort(string.compare)
        |> list.map(fn(key) {
          let assert Ok(value) = ir.metadata.misc |> dict.get(key)
          hcl.StringLiteral(key <> ":" <> value)
        }),
      ),
    )

  use window_in_days_string <- result.try(window_to_timeframe(window_in_days))

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

  Ok(terraform.Resource(
    type_: "datadog_service_level_objective",
    name: resource_name,
    attributes: dict.from_list([
      #("name", hcl.StringLiteral(ir.metadata.friendly_label)),
      #("type", hcl.StringLiteral(type_str)),
      #("tags", tags),
    ]),
    blocks: list.append(slo_blocks, [thresholds_block]),
    meta: hcl.empty_meta(),
    lifecycle: option.None,
  ))
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
