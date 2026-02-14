import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/ir.{type IntermediateRepresentation}
import gleam/dict
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
  generator_utils.generate_terraform(
    irs,
    settings: terraform_settings(),
    provider: provider(),
    variables: variables(),
    generate_resources: generate_resources,
  )
}

/// Generate only the Terraform resources for Honeycomb IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(#(List(terraform.Resource), List(String)), CompilationError) {
  generator_utils.generate_resources_multi(
    irs,
    mapper: ir_to_terraform_resources,
  )
}

/// Terraform settings block with required Honeycomb provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  generator_utils.build_terraform_settings(
    provider_name: constants.provider_honeycombio,
    source: "honeycombio/honeycombio",
    version: "~> 0.31",
  )
}

/// Honeycomb provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  generator_utils.build_provider(
    name: constants.provider_honeycombio,
    attributes: [#("api_key", hcl.ref("var.honeycomb_api_key"))],
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
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract structured SLO fields from IR.
  use slo <- result.try(generator_utils.require_slo_fields(
    ir,
    vendor: constants.vendor_honeycomb,
  ))
  let threshold = slo.threshold
  let window_in_days = slo.window_in_days
  let indicators = slo.indicators

  // Extract the evaluation expression, then resolve it through the CQL pipeline
  // by substituting indicator names into the evaluation formula.
  use evaluation_expr <- result.try(generator_utils.require_evaluation(
    slo,
    ir,
    vendor: constants.vendor_honeycomb,
  ))
  use sli_expression <- result.try(generator_utils.resolve_cql_expression(
    evaluation_expr,
    indicators,
    ir,
    vendor: constants.vendor_honeycomb,
  ))

  let time_period = window_to_time_period(window_in_days)

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
  let slo_description = generator_utils.build_description(ir)
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

  // Build user-provided tags from structured artifact data.
  let user_tag_pairs = case ir.get_slo_fields(ir.artifact_data) {
    option.Some(slo) -> slo.tags
    option.None -> []
  }

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
  |> list.filter_map(fn(key) {
    dict.get(merged, key)
    |> result.map(fn(value) { #(key, value) })
  })
}

/// Convert window_in_days to Honeycomb time_period (in days).
/// Range (1-90) is guaranteed by the standard library type constraint.
@internal
pub fn window_to_time_period(days: Int) -> Int {
  days
}
