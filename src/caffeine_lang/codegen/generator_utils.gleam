import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/ir.{type IntermediateRepresentationMetaData}
import gleam/option
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

/// Build an HCL comment identifying the source measurement and expectation.
@internal
pub fn build_source_comment(
  metadata: IntermediateRepresentationMetaData,
) -> String {
  "# Caffeine: "
  <> metadata.org_name.value
  <> "."
  <> metadata.team_name.value
  <> "."
  <> metadata.service_name.value
  <> "."
  <> metadata.friendly_label.value
  <> " (measurement: "
  <> metadata.measurement_name.value
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

/// Build a codegen resolution error with empty context.
@internal
pub fn resolution_error(
  vendor vendor_name: String,
  msg msg: String,
) -> CompilationError {
  errors.generator_terraform_resolution_error(vendor: vendor_name, msg:)
}
