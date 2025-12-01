import caffeine_lang_v2/common/ast
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/generator/common
import caffeine_lang_v2/generator/datadog
import caffeine_lang_v2/parser/artifacts.{
  type AcceptedProviders, Datadog, ServiceLevelObjective,
}
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import terra_madre/render
import terra_madre/terraform

/// Builds terraform settings with required providers
fn build_terraform_settings(
  providers: List(AcceptedProviders),
) -> terraform.TerraformSettings {
  let required_providers =
    providers
    |> list.map(fn(name) {
      case name {
        Datadog -> #("datadog", datadog.build_provider_requirement())
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
fn build_provider(provider: AcceptedProviders) -> terraform.Provider {
  case provider {
    Datadog -> datadog.build_provider()
  }
}

pub fn generate(abstract_syntax_tree: ast.AST) -> Result(String, String) {
  let artifacts_map =
    abstract_syntax_tree.artifacts
    |> helpers.obj_map(fn(a) { artifacts.artifact_name_to_string(a.name) })

  let blueprints_map =
    abstract_syntax_tree.blueprints |> helpers.obj_map(fn(b) { b.name })

  use expectations_with_artifacts_and_blueprints <- result.try(
    abstract_syntax_tree.expectations
    |> list.try_map(fn(expectation) {
      let assert Ok(blueprint) = dict.get(blueprints_map, expectation.blueprint)
      let assert Ok(artifact) = dict.get(artifacts_map, blueprint.artifact)

      Ok(#(artifact, blueprint, expectation))
    }),
  )

  // Build resources from expectations
  use resources <- result.try(
    expectations_with_artifacts_and_blueprints
    |> list.try_map(fn(entry) {
      let #(artifact, blueprint, expectation) = entry
      case artifact.name {
        ServiceLevelObjective(_) ->
          common.build_slo_resource(blueprint, expectation)
      }
    }),
  )

  // Determine unique providers needed
  let provider_names =
    expectations_with_artifacts_and_blueprints
    |> list.map(fn(entry) {
      let #(artifact, _blueprint, _expectation) = entry
      case artifact.name {
        ServiceLevelObjective(providers) -> providers
      }
    })
    |> list.flatten
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
