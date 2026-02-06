import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{
  type CompilationError, GeneratorDynatraceTerraformResolutionError,
}
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Generate Terraform HCL from a list of Dynatrace IntermediateRepresentations.
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

/// Generate only the Terraform resources for Dynatrace IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(List(terraform.Resource), CompilationError) {
  irs |> list.try_map(ir_to_terraform_resource)
}

/// Terraform settings block with required Dynatrace provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        constants.provider_dynatrace,
        terraform.ProviderRequirement(
          "dynatrace-oss/dynatrace",
          option.Some("~> 1.0"),
        ),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// Dynatrace provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  terraform.Provider(
    name: constants.provider_dynatrace,
    alias: option.None,
    attributes: dict.from_list([
      #("dt_env_url", hcl.ref("var.dynatrace_env_url")),
      #("dt_api_token", hcl.ref("var.dynatrace_api_token")),
    ]),
    blocks: [],
  )
}

/// Variables for Dynatrace environment URL and API token.
@internal
pub fn variables() -> List(terraform.Variable) {
  [
    terraform.Variable(
      name: "dynatrace_env_url",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Dynatrace environment URL"),
      sensitive: option.None,
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "dynatrace_api_token",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Dynatrace API token"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
  ]
}

/// Convert a single IntermediateRepresentation to a Dynatrace Terraform Resource.
/// Produces a single `dynatrace_slo_v2` resource.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation,
) -> Result(terraform.Resource, CompilationError) {
  let identifier = ir_to_identifier(ir)
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract structured SLO fields from IR.
  use slo <- result.try(
    semantic_analyzer.get_slo_fields(ir.artifact_data)
    |> option.to_result(GeneratorDynatraceTerraformResolutionError(
      msg: "expectation '" <> identifier <> "' - missing SLO artifact data",
    )),
  )

  // Extract the evaluation expression, then resolve it through the CQL pipeline.
  use evaluation_expr <- result.try(
    slo.evaluation
    |> option.to_result(GeneratorDynatraceTerraformResolutionError(
      msg: "expectation '"
      <> identifier
      <> "' - missing evaluation for Dynatrace SLO",
    )),
  )
  use metric_expression <- result.try(
    cql_generator.resolve_slo_to_expression(evaluation_expr, slo.indicators)
    |> result.map_error(fn(err) {
      GeneratorDynatraceTerraformResolutionError(
        msg: "expectation '" <> identifier <> "' - " <> err,
      )
    }),
  )

  use evaluation_window <- result.try(
    window_to_evaluation_window(slo.window_in_days)
    |> result.map_error(fn(err) { errors.prefix_error(err, identifier) }),
  )

  let description = build_description(ir)

  let resource =
    terraform.Resource(
      type_: "dynatrace_slo_v2",
      name: resource_name,
      attributes: dict.from_list([
        #("name", hcl.StringLiteral(ir.metadata.friendly_label)),
        #("enabled", hcl.BoolLiteral(True)),
        #("custom_description", hcl.StringLiteral(description)),
        #("evaluation_type", hcl.StringLiteral("AGGREGATE")),
        #("evaluation_window", hcl.StringLiteral(evaluation_window)),
        #("metric_expression", hcl.StringLiteral(metric_expression)),
        #("metric_name", hcl.StringLiteral(resource_name)),
        #("target_success", hcl.FloatLiteral(slo.threshold)),
      ]),
      blocks: [],
      meta: hcl.empty_meta(),
      lifecycle: option.None,
    )

  Ok(resource)
}

/// Build a description string for the SLO.
fn build_description(ir: IntermediateRepresentation) -> String {
  let runbook = case semantic_analyzer.get_slo_fields(ir.artifact_data) {
    option.Some(slo) -> slo.runbook
    option.None -> option.None
  }

  case runbook {
    option.Some(url) -> "[Runbook](" <> url <> ")"
    option.None ->
      "Managed by Caffeine ("
      <> ir.metadata.org_name
      <> "/"
      <> ir.metadata.team_name
      <> "/"
      <> ir.metadata.service_name
      <> ")"
  }
}

/// Convert window_in_days to Dynatrace evaluation_window format ("-{N}d").
/// Dynatrace accepts evaluation windows of 1-90 days.
@internal
pub fn window_to_evaluation_window(
  days: Int,
) -> Result(String, CompilationError) {
  case days >= 1 && days <= 90 {
    True -> Ok("-" <> int.to_string(days) <> "d")
    False ->
      Error(GeneratorDynatraceTerraformResolutionError(
        msg: "Illegal window_in_days value: "
        <> int.to_string(days)
        <> ". Dynatrace accepts values between 1 and 90.",
      ))
  }
}
