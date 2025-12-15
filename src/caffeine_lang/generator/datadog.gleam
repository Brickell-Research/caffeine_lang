import caffeine_lang/common/constants
import caffeine_lang/common/errors.{
  type CompilationError, GeneratorSloQueryResolutionError,
}
import caffeine_lang/common/helpers.{type ValueTuple}
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

  // Extract values from IR
  let threshold = extract_float(ir.values, "threshold") |> result.unwrap(99.9)
  let window_in_days =
    extract_int(ir.values, "window_in_days") |> result.unwrap(30)
  let queries =
    extract_dict_string_string(ir.values, "queries")
    |> result.unwrap(dict.new())
  let value_expr =
    extract_string(ir.values, "value")
    |> result.unwrap("numerator / denominator")

  // Parse the value expression using CQL and get HCL blocks
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

  // Build tags (common to both types)
  let tags =
    hcl.ListExpr([
      hcl.StringLiteral("managed_by:caffeine"),
      hcl.StringLiteral("caffeine_version:" <> constants.version),
      hcl.StringLiteral("org:" <> ir.metadata.org_name),
      hcl.StringLiteral("team:" <> ir.metadata.team_name),
      hcl.StringLiteral("service:" <> ir.metadata.service_name),
      hcl.StringLiteral("blueprint:" <> ir.metadata.blueprint_name),
      hcl.StringLiteral("expectation:" <> ir.metadata.friendly_label),
      hcl.StringLiteral("artifact:" <> ir.artifact_ref),
    ])

  // Build the thresholds block (common to both types)
  let thresholds_block =
    hcl.simple_block("thresholds", [
      #("timeframe", hcl.StringLiteral(window_to_timeframe(window_in_days))),
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
pub fn window_to_timeframe(days: Int) -> String {
  int.to_string(days) <> "d"
}

/// Extract a String value from a list of ValueTuple by label.
@internal
pub fn extract_string(
  values: List(ValueTuple),
  label: String,
) -> Result(String, Nil) {
  values
  |> list.filter(fn(vt) { vt.label == label })
  |> list.first
  |> result.try(fn(vt) {
    decode.run(vt.value, decode.string) |> result.replace_error(Nil)
  })
}

/// Extract a Float value from a list of ValueTuple by label.
@internal
pub fn extract_float(
  values: List(ValueTuple),
  label: String,
) -> Result(Float, Nil) {
  values
  |> list.filter(fn(vt) { vt.label == label })
  |> list.first
  |> result.try(fn(vt) {
    decode.run(vt.value, decode.float) |> result.replace_error(Nil)
  })
}

/// Extract an Int value from a list of ValueTuple by label.
@internal
pub fn extract_int(values: List(ValueTuple), label: String) -> Result(Int, Nil) {
  values
  |> list.filter(fn(vt) { vt.label == label })
  |> list.first
  |> result.try(fn(vt) {
    decode.run(vt.value, decode.int) |> result.replace_error(Nil)
  })
}

/// Extract a Dict(String, String) value from a list of ValueTuple by label.
@internal
pub fn extract_dict_string_string(
  values: List(ValueTuple),
  label: String,
) -> Result(dict.Dict(String, String), Nil) {
  values
  |> list.filter(fn(vt) { vt.label == label })
  |> list.first
  |> result.try(fn(vt) {
    decode.run(vt.value, decode.dict(decode.string, decode.string))
    |> result.replace_error(Nil)
  })
}
