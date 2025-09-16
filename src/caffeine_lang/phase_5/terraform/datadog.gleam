import caffeine_lang/types/ast
import caffeine_lang/types/intermediate_representation.{type ResolvedSlo}
import gleam/dict
import gleam/float
import gleam/list
import gleam/string

pub fn provider() -> String {
  "terraform {
required_providers {
    datadog = {
      source  = \"DataDog/datadog\"
      version = \"~> 3.0\"
    }
  }
}

provider \"datadog\" {
  api_key = var.DATADOG_API_KEY
  app_key = var.DATADOG_APP_KEY
}"
}

pub fn variables() -> String {
  "variable \"DATADOG_API_KEY\" {
  type        = string
  description = \"Datadog API key\"
  sensitive   = true
  default     = null
}

variable \"DATADOG_APP_KEY\" {
  type        = string
  description = \"Datadog Application key\"
  sensitive   = true
  default     = null
}"
}

pub fn provider_with_variables() -> String {
  provider() <> "\n\n" <> variables()
}

// pub fn slo_definition_to_tf(
//   slo: ast.Slo,
//   sli_type: ast.SliType,
// ) -> String {
//   todo
// }

pub fn set_resource_comment_header(team: String, sli_type: String) -> String {
  "# SLO created by EzSLO for " <> team <> " - Type: " <> sli_type
}

fn resource_name(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  team_name <> "_" <> service_name <> "_" <> sli_type
}

pub fn resource_top_line(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  "resource \"datadog_service_level_objective\" "
  <> resource_name(team_name, service_name, sli_type)
  <> " {"
}

pub fn tf_resource_name(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  "resource \"datadog_service_level_objective\" "
  <> resource_name(team_name, service_name, sli_type)
  <> " {"
}

pub fn resource_type(query_template_type: ast.QueryTemplateType) -> String {
  case query_template_type {
    ast.QueryTemplateType(_metric_attributes, _name) ->
      "type        = \"metric\""
  }
}

// TODO: allow this to be configurable
pub fn resource_description() -> String {
  "description = \"SLO created by caffeine\""
}

pub fn resource_threshold(threshold: Float) -> String {
  "thresholds {
    timeframe = \"30d\"
    target    = " <> float.to_string(threshold) <> "
  }"
}

// TODO: allow this to be configurable
pub fn resource_time_frame() -> String {
  "timeframe = \"30d\""
}

pub fn resource_target_threshold(threshold: Float) -> String {
  "target = " <> float.to_string(threshold)
}

pub fn slo_specification(slo: ResolvedSlo) -> String {
  let metric_attributes =
    slo.sli.metric_attributes
    |> dict.keys()
    |> list.sort(fn(a, b) { string.compare(a, b) })
    |> list.map(fn(key) {
      let assert Ok(value) = dict.get(slo.sli.metric_attributes, key)
      key <> " = " <> value
    })
    |> string.join("\n")

  "query {\n" <> metric_attributes <> "\n}\n"
}

pub fn get_tags(tags: dict.Dict(String, String)) -> String {
  let formatted_tags =
    tags
    |> dict.to_list()
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) {
      let #(key, value) = pair
      "\"" <> key <> ":" <> value <> "\""
    })
    |> string.join(", ")

  "tags = [" <> formatted_tags <> "]"
}
