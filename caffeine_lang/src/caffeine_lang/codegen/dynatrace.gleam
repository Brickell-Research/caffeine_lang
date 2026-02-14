import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/ir.{type IntermediateRepresentation}
import gleam/dict
import gleam/int
import gleam/option
import gleam/result
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Generate Terraform HCL from a list of Dynatrace IntermediateRepresentations.
pub fn generate_terraform(
  irs: List(IntermediateRepresentation),
) -> Result(String, CompilationError) {
  generator_utils.generate_terraform(
    irs,
    settings: terraform_settings(),
    provider: provider(),
    variables: variables(),
    generate_resources: generate_resources,
  )
}

/// Generate only the Terraform resources for Dynatrace IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(#(List(terraform.Resource), List(String)), CompilationError) {
  generator_utils.generate_resources_simple(
    irs,
    mapper: ir_to_terraform_resource,
  )
}

/// Terraform settings block with required Dynatrace provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  generator_utils.build_terraform_settings(
    provider_name: constants.provider_dynatrace,
    source: "dynatrace-oss/dynatrace",
    version: "~> 1.0",
  )
}

/// Dynatrace provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  generator_utils.build_provider(
    name: constants.provider_dynatrace,
    attributes: [
      #("dt_env_url", hcl.ref("var.dynatrace_env_url")),
      #("dt_api_token", hcl.ref("var.dynatrace_api_token")),
    ],
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
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract structured SLO fields from IR.
  use slo <- result.try(generator_utils.require_slo_fields(
    ir,
    vendor: constants.vendor_dynatrace,
  ))

  // Extract the evaluation expression, then resolve it through the CQL pipeline.
  use evaluation_expr <- result.try(generator_utils.require_evaluation(
    slo,
    ir,
    vendor: constants.vendor_dynatrace,
  ))
  use metric_expression <- result.try(generator_utils.resolve_cql_expression(
    evaluation_expr,
    slo.indicators,
    ir,
    vendor: constants.vendor_dynatrace,
  ))

  let evaluation_window = window_to_evaluation_window(slo.window_in_days)

  let description = generator_utils.build_description(ir)

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

/// Convert window_in_days to Dynatrace evaluation_window format ("-{N}d").
/// Range (1-90) is guaranteed by the standard library type constraint.
@internal
pub fn window_to_evaluation_window(days: Int) -> String {
  "-" <> int.to_string(days) <> "d"
}
