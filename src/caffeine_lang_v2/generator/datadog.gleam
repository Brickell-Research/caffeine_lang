import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import gleam/dict
import gleam/int
import gleam/option
import gleam/string
import terra_madre/hcl
import terra_madre/terraform

pub fn build_provider() -> terraform.Provider {
  terraform.simple_provider("datadog", [
    #("api_key", hcl.ref("var.datadog_api_key")),
    #("app_key", hcl.ref("var.datadog_app_key")),
  ])
}

pub fn build_provider_requirement() -> terraform.ProviderRequirement {
  terraform.ProviderRequirement(source: "DataDog/datadog", version: option.None)
}

pub fn build_slo(
  expectation expectation: Expectation,
  blueprint blueprint: Blueprint,
  query_template query_template: String,
  window_in_days window_in_days: Int,
  threshold threshold: Float,
) -> terraform.Resource {
  let resource_name =
    expectation.name
    |> string.replace("-", "_")
    |> string.replace(" ", "_")
    |> string.lowercase

  terraform.Resource(
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
  )
}
