import caffeine_lang/common/constants
import caffeine_lang/common/errors.{
  type CompilationError, GeneratorDatadogTerraformResolutionError,
  GeneratorSloQueryResolutionError,
}
import caffeine_lang/common/helpers
import caffeine_lang/core/logger
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_query_language/generator as cql_generator
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import terra_madre/common
import terra_madre/hcl
import terra_madre/render
import terra_madre/terraform

/// Generate Terraform HCL from a list of Datadog IntermediateRepresentations.
/// Includes provider configuration and variables.
pub fn generate_terraform(
  irs: List(IntermediateRepresentation),
) -> Result(String, CompilationError) {
  use resources <- result.try(irs |> list.try_map(ir_to_terraform_resource))
  let config =
    terraform.Config(
      terraform: option.Some(terraform_settings()),
      providers: [provider()],
      resources: resources,
      data_sources: [],
      variables: variables(),
      outputs: [],
      locals: [],
      modules: [],
    )
  Ok(render.render_config(config))
}

/// Terraform settings block with required Datadog provider.
@internal
pub fn terraform_settings() -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        constants.vendor_datadog,
        terraform.ProviderRequirement("DataDog/datadog", option.Some("~> 3.0")),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// Datadog provider configuration using variables for credentials.
@internal
pub fn provider() -> terraform.Provider {
  terraform.Provider(
    name: constants.vendor_datadog,
    alias: option.None,
    attributes: dict.from_list([
      #("api_key", hcl.ref("var.datadog_api_key")),
      #("app_key", hcl.ref("var.datadog_app_key")),
    ]),
    blocks: [],
  )
}

/// Variables for Datadog API credentials.
@internal
pub fn variables() -> List(terraform.Variable) {
  [
    terraform.Variable(
      name: "datadog_api_key",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Datadog API key"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
    terraform.Variable(
      name: "datadog_app_key",
      type_constraint: option.Some(hcl.Identifier("string")),
      default: option.None,
      description: option.Some("Datadog Application key"),
      sensitive: option.Some(True),
      nullable: option.None,
      validation: [],
    ),
  ]
}

/// Convert a single IntermediateRepresentation to a Terraform Resource.
/// Uses CQL to parse the value expression and generate HCL blocks.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation,
) -> Result(terraform.Resource, CompilationError) {
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  // Extract values from IR.
  let threshold =
    helpers.extract_value(ir.values, "threshold", decode.float)
    |> result.unwrap(99.9)
  let window_in_days =
    helpers.extract_value(ir.values, "window_in_days", decode.int)
    |> result.unwrap(30)
  let queries =
    helpers.extract_value(
      ir.values,
      "queries",
      decode.dict(decode.string, decode.string),
    )
    |> result.unwrap(dict.new())
  let value_expr =
    helpers.extract_value(ir.values, "value", decode.string)
    |> result.unwrap("numerator / denominator")
  let runbook =
    helpers.extract_value(
      ir.values,
      "runbook",
      decode.optional(decode.string),
    )
    |> result.unwrap(option.None)

  // Parse the value expression using CQL and get HCL blocks.
  use cql_generator.ResolvedSloHcl(slo_type, slo_blocks) <- result.try(
    cql_generator.resolve_slo_to_hcl(value_expr, queries)
    |> result.map_error(fn(err) {
      GeneratorSloQueryResolutionError(
        msg: "expectation '"
        <> ir_to_identifier(ir)
        <> "' - failed to resolve SLO query: "
        <> err,
      )
    }),
  )

  // Build dependency relation tags if artifact refs include DependencyRelations.
  let dependency_tags = case
    ir.artifact_refs |> list.contains("DependencyRelations")
  {
    True -> build_dependency_tags(ir.values)
    False -> []
  }

  // Build user-provided tags.
  let user_tags = build_user_tags(ir.values)

  // Build system tags (common to both types).
  let system_tags = [
    hcl.StringLiteral("managed_by:caffeine"),
    hcl.StringLiteral("caffeine_version:" <> constants.version),
    hcl.StringLiteral("org:" <> ir.metadata.org_name),
    hcl.StringLiteral("team:" <> ir.metadata.team_name),
    hcl.StringLiteral("service:" <> ir.metadata.service_name),
    hcl.StringLiteral("blueprint:" <> ir.metadata.blueprint_name),
    hcl.StringLiteral("expectation:" <> ir.metadata.friendly_label),
  ]
  |> list.append(
    // Generate artifact tags for each referenced artifact
    ir.artifact_refs
    |> list.map(fn(ref) { hcl.StringLiteral("artifact:" <> ref) }),
  )
  |> list.append(dependency_tags)
  |> list.append(
    // Also add misc tags (sorted for deterministic output across targets).
    ir.metadata.misc
    |> dict.keys
    |> list.sort(string.compare)
    |> list.map(fn(key) {
      let assert Ok(value) = ir.metadata.misc |> dict.get(key)
      hcl.StringLiteral(key <> ":" <> value)
    }),
  )

  // Detect overshadowing: user tags whose key matches a system tag key.
  let system_tag_keys =
    system_tags
    |> list.filter_map(fn(expr) {
      case expr {
        hcl.StringLiteral(s) ->
          case string.split_once(s, ":") {
            Ok(#(key, _)) -> Ok(key)
            Error(_) -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
    |> set.from_list

  let user_tag_keys =
    user_tags
    |> list.filter_map(fn(expr) {
      case expr {
        hcl.StringLiteral(s) ->
          case string.split_once(s, ":") {
            Ok(#(key, _)) -> Ok(key)
            Error(_) -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
    |> set.from_list

  let overlapping_keys = set.intersection(system_tag_keys, user_tag_keys)

  // Warn about overshadowing and filter out overshadowed system tags.
  let final_system_tags = case set.size(overlapping_keys) > 0 {
    True -> {
      overlapping_keys
      |> set.to_list
      |> list.sort(string.compare)
      |> list.each(fn(key) {
        logger.warn(
          ir_to_identifier(ir)
          <> " - user tag '"
          <> key
          <> "' overshadows system tag",
        )
      })
      system_tags
      |> list.filter(fn(expr) {
        case expr {
          hcl.StringLiteral(s) ->
            case string.split_once(s, ":") {
              Ok(#(key, _)) -> !set.contains(overlapping_keys, key)
              Error(_) -> True
            }
          _ -> True
        }
      })
    }
    False -> system_tags
  }

  let tags = hcl.ListExpr(list.append(final_system_tags, user_tags))

  let identifier = ir_to_identifier(ir)

  use window_in_days_string <- result.try(
    window_to_timeframe(window_in_days)
    |> result.map_error(fn(err) { errors.prefix_error(err, identifier) }),
  )

  // Build the thresholds block (common to both types).
  let thresholds_block =
    hcl.simple_block("thresholds", [
      #("timeframe", hcl.StringLiteral(window_in_days_string)),
      #("target", hcl.FloatLiteral(threshold)),
    ])

  let type_str = case slo_type {
    cql_generator.TimeSliceSlo -> "time_slice"
    cql_generator.MetricSlo -> "metric"
  }

  let base_attributes = [
    #("name", hcl.StringLiteral(ir.metadata.friendly_label)),
    #("type", hcl.StringLiteral(type_str)),
    #("tags", tags),
  ]

  let attributes = case runbook {
    option.Some(url) -> [
      #("description", hcl.StringLiteral("[Runbook](" <> url <> ")")),
      ..base_attributes
    ]
    option.None -> base_attributes
  }

  Ok(terraform.Resource(
    type_: "datadog_service_level_objective",
    name: resource_name,
    attributes: dict.from_list(attributes),
    blocks: list.append(slo_blocks, [thresholds_block]),
    meta: hcl.empty_meta(),
    lifecycle: option.None,
  ))
}

/// Build dependency relation tags from the "relations" value.
/// Extracts the relations dict (maps relation type to list of targets) and generates
/// tags like "soft_dependency:target1,target2", "hard_dependency:target3,target4".
fn build_dependency_tags(values: List(helpers.ValueTuple)) -> List(hcl.Expr) {
  let relations_dict =
    helpers.extract_value(
      values,
      "relations",
      decode.dict(decode.string, decode.list(decode.string)),
    )
    |> result.unwrap(dict.new())

  relations_dict
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) {
    let #(relation_type, targets) = pair
    let sorted_targets = targets |> list.sort(string.compare)
    hcl.StringLiteral(
      relation_type <> "_dependency:" <> string.join(sorted_targets, ","),
    )
  })
}

/// Convert window_in_days to Datadog timeframe string.
@internal
pub fn window_to_timeframe(days: Int) -> Result(String, CompilationError) {
  let days_string = int.to_string(days)
  case days {
    7 | 30 | 90 -> Ok(days_string <> "d")
    // TODO: catch this earlier on in the compilation pipeline. Possible with RefinementTypes 😁
    _ ->
      Error(GeneratorDatadogTerraformResolutionError(
        msg: "Illegal window_in_days value: "
        <> days_string
        <> ". Accepted values are 7, 30, or 90.",
      ))
  }
}

/// Build user-provided tags from the "tags" value.
/// Extracts the optional Dict(String, String) and converts to "key:value" tag strings.
fn build_user_tags(values: List(helpers.ValueTuple)) -> List(hcl.Expr) {
  let tags_dict =
    helpers.extract_value(
      values,
      "tags",
      decode.optional(decode.dict(decode.string, decode.string)),
    )
    |> result.unwrap(option.None)
    |> option.unwrap(dict.new())

  tags_dict
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) {
    let #(key, value) = pair
    hcl.StringLiteral(key <> ":" <> value)
  })
}

