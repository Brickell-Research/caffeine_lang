import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{
  type CompilationError, GeneratorTerraformResolutionError,
}
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Generate Terraform HCL from a list of New Relic IntermediateRepresentations.
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

/// Generate only the Terraform resources for New Relic IRs (no config/provider).
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(List(terraform.Resource), CompilationError) {
  irs |> list.try_map(ir_to_terraform_resource)
}

/// Terraform settings block with required New Relic provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        constants.provider_newrelic,
        terraform.ProviderRequirement(
          "newrelic/newrelic",
          option.Some("~> 3.0"),
        ),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// New Relic provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  terraform.Provider(
    name: constants.provider_newrelic,
    alias: option.None,
    attributes: dict.from_list([
      #("account_id", hcl.ref("var.newrelic_account_id")),
      #("api_key", hcl.ref("var.newrelic_api_key")),
      #("region", hcl.ref("var.newrelic_region")),
    ]),
    blocks: [],
  )
}

/// Variables for New Relic account ID, API key, and region.
@internal
pub fn variables() -> List(terraform.Variable) {
  [
    terraform.Variable(
      name: "newrelic_account_id",
      type_constraint: option.Some(hcl.Identifier("number")),
      default: option.None,
      description: option.Some("New Relic account ID"),
      sensitive: option.None,
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "newrelic_api_key",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("New Relic API key"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "newrelic_region",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.Some(hcl.StringLiteral("US")),
      description: option.Some("New Relic region"),
      sensitive: option.None,
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "newrelic_entity_guid",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("New Relic entity GUID"),
      sensitive: option.None,
      nullable: option.None,
      validation: [],
    ),
  ]
}

/// Convert a single IntermediateRepresentation to a New Relic Terraform Resource.
/// Produces a single `newrelic_service_level` resource.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation,
) -> Result(terraform.Resource, CompilationError) {
  let identifier = ir_to_identifier(ir)
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract structured SLO fields from IR.
  use slo <- result.try(
    semantic_analyzer.get_slo_fields(ir.artifact_data)
    |> option.to_result(GeneratorTerraformResolutionError(
      vendor: constants.vendor_newrelic,
      msg: "expectation '" <> identifier <> "' - missing SLO artifact data",
      context: errors.empty_context(),
    )),
  )

  // Extract the evaluation expression, then resolve it through the CQL pipeline.
  use evaluation_expr <- result.try(
    slo.evaluation
    |> option.to_result(GeneratorTerraformResolutionError(
      vendor: constants.vendor_newrelic,
      msg: "expectation '"
        <> identifier
        <> "' - missing evaluation for New Relic SLO",
      context: errors.empty_context(),
    )),
  )
  use _ <- result.try(
    cql_generator.resolve_slo_to_expression(evaluation_expr, slo.indicators)
    |> result.map_error(fn(err) {
      GeneratorTerraformResolutionError(
        vendor: constants.vendor_newrelic,
        msg: "expectation '" <> identifier <> "' - " <> err,
        context: errors.empty_context(),
      )
    }),
  )

  use rolling_count <- result.try(
    window_to_rolling_count(slo.window_in_days)
    |> result.map_error(fn(err) { errors.prefix_error(err, identifier) }),
  )

  // Build the events block from indicators.
  use events_block <- result.try(build_events_block(
    slo.indicators,
    evaluation_expr,
    identifier,
  ))

  let description = build_description(ir)

  let resource =
    terraform.Resource(
      type_: "newrelic_service_level",
      name: resource_name,
      attributes: dict.from_list([
        #("guid", hcl.ref("var.newrelic_entity_guid")),
        #("name", hcl.StringLiteral(ir.metadata.friendly_label)),
        #("description", hcl.StringLiteral(description)),
      ]),
      blocks: [
        events_block,
        hcl.Block(
          type_: "objective",
          labels: [],
          attributes: dict.from_list([
            #("target", hcl.FloatLiteral(slo.threshold)),
          ]),
          blocks: [
            hcl.Block(
              type_: "time_window",
              labels: [],
              attributes: dict.new(),
              blocks: [
                hcl.simple_block("rolling", [
                  #("count", hcl.IntLiteral(rolling_count)),
                  #("unit", hcl.StringLiteral("DAY")),
                ]),
              ],
            ),
          ],
        ),
      ],
      meta: hcl.empty_meta(),
      lifecycle: option.None,
    )

  Ok(resource)
}

/// Build the events block from indicators and evaluation expression.
/// Determines which indicators map to valid_events and good_events based
/// on the evaluation expression structure (numerator = good, denominator = valid).
fn build_events_block(
  indicators: dict.Dict(String, String),
  evaluation_expr: String,
  identifier: String,
) -> Result(hcl.Block, CompilationError) {
  // The evaluation expression is expected to be "good / valid" format.
  // The numerator indicator maps to good_events, denominator to valid_events.
  let indicator_names = dict.keys(indicators)
  use #(good_name, valid_name) <- result.try(extract_good_valid_names(
    evaluation_expr,
    indicator_names,
    identifier,
  ))

  use good_indicator <- result.try(
    dict.get(indicators, good_name)
    |> result.replace_error(GeneratorTerraformResolutionError(
      vendor: constants.vendor_newrelic,
      msg: "expectation '"
        <> identifier
        <> "' - indicator '"
        <> good_name
        <> "' not found",
      context: errors.empty_context(),
    )),
  )
  use valid_indicator <- result.try(
    dict.get(indicators, valid_name)
    |> result.replace_error(GeneratorTerraformResolutionError(
      vendor: constants.vendor_newrelic,
      msg: "expectation '"
        <> identifier
        <> "' - indicator '"
        <> valid_name
        <> "' not found",
      context: errors.empty_context(),
    )),
  )

  let #(good_from, good_where) = parse_nrql_indicator(good_indicator)
  let #(valid_from, valid_where) = parse_nrql_indicator(valid_indicator)

  let good_events_block =
    build_nrql_event_block("good_events", good_from, good_where)
  let valid_events_block =
    build_nrql_event_block("valid_events", valid_from, valid_where)

  Ok(
    hcl.Block(
      type_: "events",
      labels: [],
      attributes: dict.from_list([
        #("account_id", hcl.ref("var.newrelic_account_id")),
      ]),
      blocks: [valid_events_block, good_events_block],
    ),
  )
}

/// Extract good and valid indicator names from the evaluation expression.
/// Expects a "numerator / denominator" pattern where numerator = good, denominator = valid.
fn extract_good_valid_names(
  evaluation_expr: String,
  indicator_names: List(String),
  identifier: String,
) -> Result(#(String, String), CompilationError) {
  case string.split(evaluation_expr, " / ") {
    [good, valid] -> {
      let good_trimmed = string.trim(good)
      let valid_trimmed = string.trim(valid)
      case
        list.contains(indicator_names, good_trimmed)
        && list.contains(indicator_names, valid_trimmed)
      {
        True -> Ok(#(good_trimmed, valid_trimmed))
        False ->
          Error(GeneratorTerraformResolutionError(
            vendor: constants.vendor_newrelic,
            msg: "expectation '"
              <> identifier
              <> "' - evaluation references indicators not found in indicator map",
            context: errors.empty_context(),
          ))
      }
    }
    _ ->
      Error(GeneratorTerraformResolutionError(
        vendor: constants.vendor_newrelic,
        msg: "expectation '"
          <> identifier
          <> "' - evaluation must be in 'good / valid' format for New Relic",
        context: errors.empty_context(),
      ))
  }
}

/// Parse a NRQL indicator string into (from, optional where) components.
/// Format: "EventType" or "EventType WHERE condition".
@internal
pub fn parse_nrql_indicator(
  indicator: String,
) -> #(String, option.Option(String)) {
  case string.split(indicator, " WHERE ") {
    [from] -> #(from, option.None)
    [from, ..rest] -> #(from, option.Some(string.join(rest, " WHERE ")))
    _ -> #(indicator, option.None)
  }
}

/// Build an NRQL event sub-block (good_events or valid_events).
fn build_nrql_event_block(
  block_type: String,
  from: String,
  where_clause: option.Option(String),
) -> hcl.Block {
  let attrs = case where_clause {
    option.Some(where) -> [
      #("from", hcl.StringLiteral(from)),
      #("where", hcl.StringLiteral(where)),
    ]
    option.None -> [#("from", hcl.StringLiteral(from))]
  }
  hcl.Block(
    type_: block_type,
    labels: [],
    attributes: dict.from_list(attrs),
    blocks: [],
  )
}

/// Convert window_in_days to New Relic rolling count.
/// New Relic only accepts 1, 7, or 28 day windows.
@internal
pub fn window_to_rolling_count(days: Int) -> Result(Int, CompilationError) {
  case days {
    1 | 7 | 28 -> Ok(days)
    _ ->
      Error(GeneratorTerraformResolutionError(
        vendor: constants.vendor_newrelic,
        msg: "Illegal window_in_days value: "
          <> int.to_string(days)
          <> ". New Relic accepts only 1, 7, or 28.",
        context: errors.empty_context(),
      ))
  }
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
