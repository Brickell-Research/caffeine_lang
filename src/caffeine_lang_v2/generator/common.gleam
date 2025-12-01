import caffeine_lang_v2/generator/datadog
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import gleam/dict
import gleam/float
import gleam/int
import gleam/result
import gleam/string
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

  Ok(datadog.build_slo(
    expectation:,
    blueprint:,
    query_template:,
    window_in_days:,
    threshold:,
  ))
}
