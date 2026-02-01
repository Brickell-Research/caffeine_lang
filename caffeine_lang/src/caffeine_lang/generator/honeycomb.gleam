import caffeine_lang/common/constants
import caffeine_lang/common/errors.{
  type CompilationError, GeneratorHoneycombTerraformResolutionError,
}
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
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

/// Generate Terraform HCL from a list of Honeycomb IntermediateRepresentations.
pub fn generate_terraform(
  irs: List(IntermediateRepresentation),
) -> Result(String, CompilationError) {
  use resources <- result.try(irs |> list.try_map(ir_to_terraform_resources))
  let config =
    terraform.Config(
      terraform: option.Some(terraform_settings()),
      providers: [provider()],
      resources: list.flatten(resources),
      data_sources: [],
      variables: variables(),
      outputs: [],
      locals: [],
      modules: [],
    )
  Ok(render.render_config(config))
}

/// Terraform settings block with required Honeycomb provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        "honeycombio",
        terraform.ProviderRequirement(
          "honeycombio/honeycombio",
          option.Some("~> 0.31"),
        ),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// Honeycomb provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  terraform.Provider(
    name: "honeycombio",
    alias: option.None,
    attributes: dict.from_list([
      #("api_key", hcl.ref("var.honeycomb_api_key")),
    ]),
    blocks: [],
  )
}

/// Variables for Honeycomb API credentials and dataset.
@internal
pub fn variables() -> List(terraform.Variable) {
  [
    terraform.Variable(
      name: "honeycomb_api_key",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Honeycomb API key"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "honeycomb_dataset",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Honeycomb dataset slug"),
      sensitive: option.None,
      nullable: option.None,
      validation: [],
    ),
  ]
}

/// Convert a single IntermediateRepresentation to Honeycomb Terraform Resources.
/// Produces a derived_column for the SLI and an SLO that references it.
@internal
pub fn ir_to_terraform_resources(
  ir: IntermediateRepresentation,
) -> Result(List(terraform.Resource), CompilationError) {
  let identifier = ir_to_identifier(ir)
  let resource_name =
    common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract values from IR.
  let threshold =
    helpers.extract_value(ir.values, "threshold", decode.float)
    |> result.unwrap(99.9)
  let window_in_days =
    helpers.extract_value(ir.values, "window_in_days", decode.int)
    |> result.unwrap(30)
  let indicators =
    helpers.extract_value(
      ir.values,
      "indicators",
      decode.dict(decode.string, decode.string),
    )
    |> result.unwrap(dict.new())

  // For Honeycomb, we expect a single indicator with a boolean SLI expression.
  // Get the first indicator value as the SLI expression.
  use sli_expression <- result.try(
    indicators
    |> dict.values
    |> list.first
    |> result.replace_error(GeneratorHoneycombTerraformResolutionError(
      msg: "expectation '"
      <> identifier
      <> "' - no indicators defined for Honeycomb SLO",
    )),
  )

  use time_period <- result.try(
    window_to_time_period(window_in_days)
    |> result.map_error(fn(err) { errors.prefix_error(err, identifier) }),
  )

  let derived_column_alias = resource_name <> "_sli"

  // Resource 1: honeycombio_derived_column for the SLI.
  let derived_column =
    terraform.Resource(
      type_: "honeycombio_derived_column",
      name: derived_column_alias,
      attributes: dict.from_list([
        #("alias", hcl.StringLiteral(derived_column_alias)),
        #("expression", hcl.StringLiteral(sli_expression)),
        #("dataset", hcl.ref("var.honeycomb_dataset")),
      ]),
      blocks: [],
      meta: hcl.empty_meta(),
      lifecycle: option.None,
    )

  // Resource 2: honeycombio_slo.
  let slo_description = build_description(ir)
  let slo_attributes = [
    #("name", hcl.StringLiteral(ir.metadata.friendly_label)),
    #("description", hcl.StringLiteral(slo_description)),
    #("dataset", hcl.ref("var.honeycomb_dataset")),
    #(
      "sli",
      hcl.ref(
        "honeycombio_derived_column." <> derived_column_alias <> ".alias",
      ),
    ),
    #("target_percentage", hcl.FloatLiteral(threshold)),
    #("time_period", hcl.IntLiteral(time_period)),
    #("tags", build_tags(ir)),
  ]

  let slo =
    terraform.Resource(
      type_: "honeycombio_slo",
      name: resource_name,
      attributes: dict.from_list(slo_attributes),
      blocks: [],
      meta: hcl.empty_meta(),
      lifecycle: option.None,
    )

  Ok([derived_column, slo])
}

/// Build a description string for the SLO.
fn build_description(ir: IntermediateRepresentation) -> String {
  let runbook =
    helpers.extract_value(
      ir.values,
      "runbook",
      decode.optional(decode.string),
    )
    |> result.unwrap(option.None)

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

/// Build tags as a map expression for Honeycomb.
/// Honeycomb uses a map of string to string for tags.
fn build_tags(ir: IntermediateRepresentation) -> hcl.Expr {
  let system_tags = [
    #("managed_by", "caffeine"),
    #("caffeine_version", constants.version),
    #("org", ir.metadata.org_name),
    #("team", ir.metadata.team_name),
    #("service", ir.metadata.service_name),
    #("blueprint", ir.metadata.blueprint_name),
    #("expectation", ir.metadata.friendly_label),
  ]

  // Add misc metadata tags.
  let misc_tags =
    ir.metadata.misc
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) {
      let #(key, values) = pair
      let sorted_values = values |> list.sort(string.compare)
      #(key, string.join(sorted_values, ","))
    })

  // Build user-provided tags.
  let user_tags =
    helpers.extract_value(
      ir.values,
      "tags",
      decode.optional(decode.dict(decode.string, decode.string)),
    )
    |> result.unwrap(option.None)
    |> option.unwrap(dict.new())
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

  let all_tags =
    list.flatten([system_tags, misc_tags, user_tags])
    |> list.map(fn(pair) {
      let #(key, value) = pair
      #(hcl.IdentKey(key), hcl.StringLiteral(value))
    })

  hcl.MapExpr(all_tags)
}

/// Convert window_in_days to Honeycomb time_period (in days).
/// Honeycomb accepts time periods of 1-90 days.
@internal
pub fn window_to_time_period(days: Int) -> Result(Int, CompilationError) {
  case days >= 1 && days <= 90 {
    True -> Ok(days)
    False ->
      Error(GeneratorHoneycombTerraformResolutionError(
        msg: "Illegal window_in_days value: "
        <> int.to_string(days)
        <> ". Honeycomb accepts values between 1 and 90.",
      ))
  }
}
