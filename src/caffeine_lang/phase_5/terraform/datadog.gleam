import caffeine_lang/phase_2/ast/types as ast_types
import caffeine_lang/phase_4/resolved/types as resolved_types
import gleam/dict
import gleam/float
import gleam/int
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

pub fn set_resource_comment_header(team: String, sli_type: String) -> String {
  "# SLO created by EzSLO for " <> team <> " - Type: " <> sli_type
}

fn resource_name(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  "name = \"" <> team_name <> "_" <> service_name <> "_" <> sli_type <> "\""
}

pub fn resource_top_line(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  "resource \"datadog_service_level_objective\" \""
  <> team_name
  <> "_"
  <> service_name
  <> "_"
  <> sli_type
  <> "\" {"
}

pub fn tf_resource_name(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  "resource \"datadog_service_level_objective\" "
  <> team_name
  <> "_"
  <> service_name
  <> "_"
  <> sli_type
  <> " {"
}

pub fn resource_type(query_template_type: ast_types.QueryTemplateType) -> String {
  case query_template_type {
    ast_types.QueryTemplateType(_metric_attributes, _name) ->
      "type        = \"metric\""
  }
}

// TODO: allow this to be configurable
pub fn resource_description() -> String {
  "description = \"SLO created by caffeine\""
}

pub fn resource_threshold(threshold: Float, time_window_in_days: Int) -> String {
  "thresholds {
    timeframe = \"" <> int.to_string(time_window_in_days) <> "d\"
    target    = " <> float.to_string(threshold) <> "
  }"
}

pub fn resource_target_threshold(threshold: Float) -> String {
  "target = " <> float.to_string(threshold)
}

pub fn slo_specification(slo: resolved_types.ResolvedSlo) -> String {
  let metric_attributes =
    slo.sli.metric_attributes
    |> dict.keys()
    |> list.sort(fn(a, b) { string.compare(a, b) })
    |> list.map(fn(key) {
      let assert Ok(value) = dict.get(slo.sli.metric_attributes, key)
      let escaped_value = string.replace(value, "\"", "\\\"")
      "    " <> key <> " = \"" <> escaped_value <> "\""
    })
    |> string.join("\n")

  "query {\n" <> metric_attributes <> "\n  }\n"
}

pub fn get_tags(
  team_name: String,
  service_name: String,
  sli_type: String,
) -> String {
  "tags = [\"managed-by:caffeine\", \"team:"
  <> team_name
  <> "\", \"service:"
  <> service_name
  <> "\", \"sli:"
  <> sli_type
  <> "\"]"
}

pub fn full_resource_body(slo: resolved_types.ResolvedSlo) -> String {
  let comment_header =
    set_resource_comment_header(slo.team_name, slo.sli.query_template_type.name)
  let resource_top_line =
    resource_top_line(
      slo.team_name,
      slo.service_name,
      slo.sli.query_template_type.name,
    )
  let resource_type = resource_type(slo.sli.query_template_type)
  let resource_description = resource_description()
  let resource_threshold = resource_threshold(slo.threshold, slo.window_in_days)
  let slo_specification = slo_specification(slo)
  let resource_name =
    resource_name(
      slo.team_name,
      slo.service_name,
      slo.sli.query_template_type.name,
    )
  let tags =
    get_tags(slo.team_name, slo.service_name, slo.sli.query_template_type.name)
  comment_header
  <> "\n"
  <> resource_top_line
  <> "\n  "
  <> resource_name
  <> "\n  "
  <> resource_type
  <> "\n  "
  <> resource_description
  <> "\n  \n  "
  <> slo_specification
  <> "\n  "
  <> resource_threshold
  <> "\n\n  "
  <> tags
  <> "\n}"
}
