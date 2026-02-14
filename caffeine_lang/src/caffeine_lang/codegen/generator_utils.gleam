import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, type IntermediateRepresentationMetaData,
  type SloFields, ir_to_identifier,
}
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import terra_madre/hcl
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
pub fn build_description(
  ir: IntermediateRepresentation,
  with slo: SloFields,
) -> String {
  case slo.runbook {
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
  |> option.to_result(resolution_error(
    vendor: vendor_name,
    msg: "expectation '"
      <> ir_to_identifier(ir)
      <> "' - missing SLO artifact data",
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
  |> option.to_result(resolution_error(
    vendor: vendor_name,
    msg: "expectation '"
      <> ir_to_identifier(ir)
      <> "' - missing evaluation for "
      <> vendor_display_name(vendor_name)
      <> " SLO",
  ))
}

/// Maps a vendor constant to a human-friendly display name.
fn vendor_display_name(vendor: String) -> String {
  case vendor {
    "datadog" -> "Datadog"
    "honeycomb" -> "Honeycomb"
    "dynatrace" -> "Dynatrace"
    "newrelic" -> "New Relic"
    other -> other
  }
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
    resolution_error(
      vendor: vendor_name,
      msg: "expectation '" <> ir_to_identifier(ir) <> "' - " <> err,
    )
  })
}

/// Build a codegen resolution error with empty context.
@internal
pub fn resolution_error(
  vendor vendor_name: String,
  msg msg: String,
) -> CompilationError {
  errors.generator_terraform_resolution_error(vendor: vendor_name, msg:)
}

/// Build a TerraformSettings block with a single required provider.
@internal
pub fn build_terraform_settings(
  provider_name provider_name: String,
  source source: String,
  version version: String,
) -> TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        provider_name,
        terraform.ProviderRequirement(source, option.Some(version)),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// Build a Provider block with the given name and attributes.
@internal
pub fn build_provider(
  name name: String,
  attributes attributes: List(#(String, hcl.Expr)),
) -> Provider {
  terraform.Provider(
    name: name,
    alias: option.None,
    attributes: dict.from_list(attributes),
    blocks: [],
  )
}

/// Generate resources by mapping each IR to a single resource.
/// Returns an empty warnings list. Suitable for vendors without per-resource warnings.
@internal
pub fn generate_resources_simple(
  irs: List(IntermediateRepresentation),
  mapper mapper: fn(IntermediateRepresentation) ->
    Result(Resource, CompilationError),
) -> Result(#(List(Resource), List(String)), CompilationError) {
  irs
  |> list.try_map(mapper)
  |> result.map(fn(r) { #(r, []) })
}

/// Generate resources by mapping each IR to a list of resources, then flattening.
/// Returns an empty warnings list. Suitable for vendors that produce multiple resources per IR.
@internal
pub fn generate_resources_multi(
  irs: List(IntermediateRepresentation),
  mapper mapper: fn(IntermediateRepresentation) ->
    Result(List(Resource), CompilationError),
) -> Result(#(List(Resource), List(String)), CompilationError) {
  irs
  |> list.try_map(mapper)
  |> result.map(fn(lists) { #(list.flatten(lists), []) })
}

/// Generate Terraform HCL by assembling resources, settings, provider, and variables.
/// Discards warnings from resource generation. Suitable for vendors whose
/// `generate_terraform` returns `Result(String, CompilationError)`.
@internal
pub fn generate_terraform(
  irs: List(IntermediateRepresentation),
  settings settings: TerraformSettings,
  provider provider: Provider,
  variables variables: List(Variable),
  generate_resources generate_resources: fn(List(IntermediateRepresentation)) ->
    Result(#(List(Resource), List(String)), CompilationError),
) -> Result(String, CompilationError) {
  use #(resources, _warnings) <- result.try(generate_resources(irs))
  Ok(render_terraform_config(
    resources: resources,
    settings: settings,
    providers: [provider],
    variables: variables,
  ))
}
