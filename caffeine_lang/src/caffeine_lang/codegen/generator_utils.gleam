import caffeine_lang/errors.{
  type CompilationError, GeneratorTerraformResolutionError,
}
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, type IntermediateRepresentationMetaData,
  type SloFields, ir_to_identifier,
}
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/option
import gleam/result
import gleam/string
import terra_madre/render
import terra_madre/terraform.{
  type Provider, type Resource, type TerraformSettings, type Variable,
}

/// Render a Terraform config from resources, settings, providers, and variables.
/// Assembles the standard Config structure and renders it to HCL.
@internal
pub fn render_terraform_config(
  resources resources: List(Resource),
  settings settings: TerraformSettings,
  providers providers: List(Provider),
  variables variables: List(Variable),
) -> String {
  let config =
    terraform.Config(
      terraform: option.Some(settings),
      providers: providers,
      resources: resources,
      data_sources: [],
      variables: variables,
      outputs: [],
      locals: [],
      modules: [],
    )
  render.render_config(config)
}

/// Build an HCL comment identifying the source blueprint and expectation.
@internal
pub fn build_source_comment(
  metadata: IntermediateRepresentationMetaData,
) -> String {
  "# Caffeine: "
  <> metadata.org_name
  <> "."
  <> metadata.team_name
  <> "."
  <> metadata.service_name
  <> "."
  <> metadata.friendly_label
  <> " (blueprint: "
  <> metadata.blueprint_name
  <> ")"
}

/// Render a single Terraform resource to HCL string (no trailing newline).
@internal
pub fn render_resource_to_string(resource: Resource) -> String {
  let config =
    terraform.Config(
      terraform: option.None,
      providers: [],
      resources: [resource],
      data_sources: [],
      variables: [],
      outputs: [],
      locals: [],
      modules: [],
    )
  render.render_config(config)
  |> string.drop_end(1)
}

/// Build a description string for an SLO resource.
/// Uses the runbook URL if present, otherwise a standard "Managed by Caffeine" message.
@internal
pub fn build_description(ir: IntermediateRepresentation) -> String {
  let runbook = case ir.get_slo_fields(ir.artifact_data) {
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

/// Extract SLO fields from IR, returning a codegen error if missing.
@internal
pub fn require_slo_fields(
  ir: IntermediateRepresentation,
  vendor vendor_name: String,
) -> Result(SloFields, CompilationError) {
  ir.get_slo_fields(ir.artifact_data)
  |> option.to_result(GeneratorTerraformResolutionError(
    vendor: vendor_name,
    msg: "expectation '"
      <> ir_to_identifier(ir)
      <> "' - missing SLO artifact data",
    context: errors.empty_context(),
  ))
}

/// Extract evaluation expression from SLO fields, returning a codegen error if missing.
@internal
pub fn require_evaluation(
  slo: SloFields,
  ir: IntermediateRepresentation,
  vendor vendor_name: String,
) -> Result(String, CompilationError) {
  slo.evaluation
  |> option.to_result(GeneratorTerraformResolutionError(
    vendor: vendor_name,
    msg: "expectation '"
      <> ir_to_identifier(ir)
      <> "' - missing evaluation for "
      <> vendor_name
      <> " SLO",
    context: errors.empty_context(),
  ))
}

/// Resolve a CQL expression by substituting indicators, wrapping errors with vendor context.
@internal
pub fn resolve_cql_expression(
  evaluation_expr: String,
  indicators: dict.Dict(String, String),
  ir: IntermediateRepresentation,
  vendor vendor_name: String,
) -> Result(String, CompilationError) {
  cql_generator.resolve_slo_to_expression(evaluation_expr, indicators)
  |> result.map_error(fn(err) {
    GeneratorTerraformResolutionError(
      vendor: vendor_name,
      msg: "expectation '" <> ir_to_identifier(ir) <> "' - " <> err,
      context: errors.empty_context(),
    )
  })
}

/// Build a codegen resolution error with empty context.
@internal
pub fn resolution_error(
  vendor vendor_name: String,
  msg msg: String,
) -> CompilationError {
  GeneratorTerraformResolutionError(
    vendor: vendor_name,
    msg: msg,
    context: errors.empty_context(),
  )
}
