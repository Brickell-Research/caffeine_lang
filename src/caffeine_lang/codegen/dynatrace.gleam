import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/ir.{type IntermediateRepresentation, type Resolved}
import gleam/dict
import gleam/int
import gleam/option
import gleam/result
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Generate only the Terraform resources for Dynatrace IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation(Resolved)),
) -> Result(#(List(terraform.Resource), List(String)), CompilationError) {
  generator_utils.generate_resources_simple(
    irs,
    mapper: ir_to_terraform_resource,
  )
}

/// Convert a single IntermediateRepresentation to a Dynatrace Terraform Resource.
/// Produces a single `dynatrace_slo_v2` resource.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation(Resolved),
) -> Result(terraform.Resource, CompilationError) {
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  let slo = ir.slo

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

  let description = generator_utils.build_description(ir, with: slo)

  let resource =
    terraform.Resource(
      type_: "dynatrace_slo_v2",
      name: resource_name,
      attributes: dict.from_list([
        #("name", hcl.StringLiteral(ir.metadata.friendly_label.value)),
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
