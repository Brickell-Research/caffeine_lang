import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{
  type CompilationError, GeneratorHoneycombTerraformResolutionError,
}
import caffeine_lang/helpers
import caffeine_lang/value
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Generate Terraform HCL from a list of Honeycomb IntermediateRepresentations.
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

/// Generate only the Terraform resources for Honeycomb IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(List(terraform.Resource), CompilationError) {
  use resource_lists <- result.try(
    irs |> list.try_map(ir_to_terraform_resources),
  )
  Ok(list.flatten(resource_lists))
}

/// Terraform settings block with required Honeycomb provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        constants.provider_honeycombio,
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
    name: constants.provider_honeycombio,
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
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract values from IR.
  let threshold = helpers.extract_threshold(ir.values)
  let window_in_days = helpers.extract_window_in_days(ir.values)
  let indicators = helpers.extract_indicators(ir.values)

  // Extract the evaluation expression, then resolve it through the CQL pipeline
  // by substituting indicator names into the evaluation formula.
  use evaluation_expr <- result.try(
    helpers.extract_value(ir.values, "evaluation", value.extract_string)
    |> result.replace_error(GeneratorHoneycombTerraformResolutionError(
      msg: "expectation '"
      <> identifier
      <> "' - missing evaluation for Honeycomb SLO",
    )),
  )
  use sli_expression <- result.try(
    cql_generator.resolve_slo_to_expression(evaluation_expr, indicators)
    |> result.map_error(fn(err) {
      GeneratorHoneycombTerraformResolutionError(
        msg: "expectation '" <> identifier <> "' - " <> err,
      )
    }),
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
      hcl.ref("honeycombio_derived_column." <> derived_column_alias <> ".alias"),
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
    helpers.extract_value(ir.values, "runbook", fn(v) {
      case v {
        value.NilValue -> Ok(option.None)
        value.StringValue(s) -> Ok(option.Some(s))
        _ -> Error(Nil)
      }
    })
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
  // Build system tags from shared helper. For Honeycomb, misc tags with multiple
  // values are joined with commas since the tag format is a flat map.
  let system_tag_pairs =
    helpers.build_system_tag_pairs(
      org_name: ir.metadata.org_name,
      team_name: ir.metadata.team_name,
      service_name: ir.metadata.service_name,
      blueprint_name: ir.metadata.blueprint_name,
      friendly_label: ir.metadata.friendly_label,
      artifact_refs: [],
      misc: ir.metadata.misc,
    )
    |> collapse_multi_value_tags

  // Build user-provided tags.
  let user_tag_pairs = helpers.extract_tags(ir.values)

  let all_tags =
    list.append(system_tag_pairs, user_tag_pairs)
    |> list.map(fn(pair) { #(hcl.IdentKey(pair.0), hcl.StringLiteral(pair.1)) })

  hcl.MapExpr(all_tags)
}

/// Collapse tag pairs that share the same key by joining values with commas.
/// The shared helper produces one pair per misc value, but Honeycomb needs a
/// single key-value entry per tag key. Preserves insertion order of first occurrence.
fn collapse_multi_value_tags(
  pairs: List(#(String, String)),
) -> List(#(String, String)) {
  let #(order, merged) =
    pairs
    |> list.fold(#([], dict.new()), fn(acc, pair) {
      let #(keys, seen) = acc
      let #(key, value) = pair
      case dict.get(seen, key) {
        Ok(existing) -> #(
          keys,
          dict.insert(seen, key, existing <> "," <> value),
        )
        Error(_) -> #([key, ..keys], dict.insert(seen, key, value))
      }
    })

  order
  |> list.reverse
  |> list.map(fn(key) {
    let assert Ok(value) = dict.get(merged, key)
    #(key, value)
  })
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
