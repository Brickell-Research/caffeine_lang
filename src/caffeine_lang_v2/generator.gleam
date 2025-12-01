import caffeine_lang_v2/common/ast
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import terra_madre/hcl
import terra_madre/render
import terra_madre/terraform

/// Builds a datadog_service_level_objective resource from an expectation
pub fn build_slo_resource(
  blueprint: Blueprint,
  expectation: Expectation,
) -> Result(terraform.Resource, String) {
  let assert Ok(threshold_str) = dict.get(expectation.inputs, "threshold")
  let assert Ok(window_str) = dict.get(expectation.inputs, "window_in_days")

  use threshold <- result.try(
    float.parse(threshold_str)
    |> result.lazy_or(fn() {
      int.parse(threshold_str) |> result.map(int.to_float)
    })
    |> result.map_error(fn(_) { "Invalid threshold value: " <> threshold_str }),
  )

  use window_in_days <- result.try(
    int.parse(window_str)
    |> result.map_error(fn(_) { "Invalid window_in_days value: " <> window_str }),
  )

  let assert Ok(query_template) = dict.get(blueprint.inputs, "value")
  let query_template =
    query_template
    |> string.trim
    |> string.replace("\"", "")

  let resource_name =
    expectation.name
    |> string.replace("-", "_")
    |> string.replace(" ", "_")
    |> string.lowercase

  Ok(terraform.Resource(
    type_: "datadog_service_level_objective",
    name: resource_name,
    attributes: dict.from_list([
      #("name", hcl.StringLiteral(expectation.name)),
      #("type", hcl.StringLiteral("metric")),
      #("description", hcl.StringLiteral("SLO managed by Caffeine")),
      #(
        "tags",
        hcl.ListExpr([
          hcl.StringLiteral("managed-by:caffeine"),
          hcl.StringLiteral("blueprint:" <> blueprint.name),
        ]),
      ),
    ]),
    blocks: [
      hcl.simple_block("query", [
        #("numerator", hcl.StringLiteral(query_template <> ".as_count()")),
        #("denominator", hcl.StringLiteral(query_template <> ".as_count()")),
      ]),
      hcl.simple_block("thresholds", [
        #("timeframe", hcl.StringLiteral(int.to_string(window_in_days) <> "d")),
        #("target", hcl.FloatLiteral(threshold)),
      ]),
    ],
    meta: hcl.empty_meta(),
    lifecycle: option.None,
  ))
}

/// Builds terraform settings with required providers
fn build_terraform_settings(
  provider_names: List(String),
) -> terraform.TerraformSettings {
  let required_providers =
    provider_names
    |> list.map(fn(name) {
      case name {
        "datadog" -> #(
          "datadog",
          terraform.ProviderRequirement(
            source: "DataDog/datadog",
            version: option.None,
          ),
        )
        _ -> #(
          name,
          terraform.ProviderRequirement(source: name, version: option.None),
        )
      }
    })
    |> dict.from_list

  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: required_providers,
    backend: option.None,
    cloud: option.None,
  )
}

/// Builds a provider block
fn build_provider(provider_name: String) -> terraform.Provider {
  case provider_name {
    "datadog" ->
      terraform.simple_provider("datadog", [
        #("api_key", hcl.ref("var.datadog_api_key")),
        #("app_key", hcl.ref("var.datadog_app_key")),
      ])
    _ -> terraform.simple_provider(provider_name, [])
  }
}

pub fn generate(abstract_syntax_tree: ast.AST) -> Result(String, String) {
  let artifacts_map =
    abstract_syntax_tree.artifacts
    |> list.map(fn(artifact) { #(artifact.name, artifact) })
    |> dict.from_list

  let blueprints_map =
    abstract_syntax_tree.blueprints
    |> list.map(fn(blueprint) { #(blueprint.name, blueprint) })
    |> dict.from_list

  // Build resources from expectations
  use resources <- result.try(
    abstract_syntax_tree.expectations
    |> list.try_map(fn(expectation) {
      let assert Ok(blueprint) = dict.get(blueprints_map, expectation.blueprint)
      let assert Ok(artifact) = dict.get(artifacts_map, blueprint.artifact)

      case artifact.name |> string.lowercase {
        "slo" -> build_slo_resource(blueprint, expectation)
        _ -> Error("Unsupported artifact type: " <> artifact.name)
      }
    }),
  )

  // Determine unique providers needed
  let provider_names =
    abstract_syntax_tree.expectations
    |> list.map(fn(expectation) {
      let assert Ok(blueprint) = dict.get(blueprints_map, expectation.blueprint)
      let assert Ok(artifact) = dict.get(artifacts_map, blueprint.artifact)
      // Map artifact to provider - currently SLO -> datadog
      case artifact.name |> string.lowercase {
        "slo" -> "datadog"
        _ -> artifact.name
      }
    })
    |> list.unique

  // Build the complete config
  let config =
    terraform.Config(
      terraform: option.Some(build_terraform_settings(provider_names)),
      providers: list.map(provider_names, build_provider),
      resources: resources,
      data_sources: [],
      variables: [],
      outputs: [],
      locals: [],
      modules: [],
    )

  Ok(render.render_config(config) |> string.trim)
}
