import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/resolved/resolved_slo
import deps/cql/generator
import deps/cql/resolver
import gleam/float
import gleam/int

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
  slo_name: String,
) -> String {
  "name = \"" <> team_name <> "_" <> service_name <> "_" <> slo_name <> "\""
}

pub fn resource_top_line(
  team_name: String,
  service_name: String,
  sli_type: String,
  index: Int,
) -> String {
  "resource \"datadog_service_level_objective\" \""
  <> team_name
  <> "_"
  <> service_name
  <> "_"
  <> sli_type
  <> "_"
  <> int.to_string(index)
  <> "\" {"
}

pub fn tf_resource_name(
  team_name: String,
  service_name: String,
  sli_type: String,
  index: Int,
) -> String {
  "resource \"datadog_service_level_objective\" "
  <> team_name
  <> "_"
  <> service_name
  <> "_"
  <> sli_type
  <> "_"
  <> int.to_string(index)
  <> " {"
}

pub fn resource_type(
  query_template_type: query_template_type.QueryTemplateType,
) -> String {
  case query_template_type {
    query_template_type.QueryTemplateType(_metric_attributes, _name, _query) ->
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

pub fn slo_specification(slo: resolved_slo.Slo) -> String {
  // Resolve the CQL query from the resolved SLI
  case resolver.resolve_primitives(slo.sli.resolved_query) {
    Ok(primitives) -> {
      // Generate the Datadog query string from the resolved primitives
      generator.generate_datadog_query(primitives)
    }
    Error(err) -> {
      err
    }
  }
}

pub fn get_tags(
  team_name: String,
  service_name: String,
  sli_type: String,
  query_type: String,
) -> String {
  "tags = [\"managed-by:caffeine\", \"team:"
  <> team_name
  <> "\", \"service:"
  <> service_name
  <> "\", \"sli_type:"
  <> sli_type
  <> "\", \"query_type:"
  <> query_type
  <> "\"]"
}

pub fn full_resource_body(slo: resolved_slo.Slo, index: Int) -> String {
  let comment_header =
    set_resource_comment_header(slo.team_name, slo.sli.query_template_type.name)
  let resource_top_line =
    resource_top_line(
      slo.team_name,
      slo.service_name,
      slo.sli.query_template_type.name,
      index,
    )
  let resource_type = resource_type(slo.sli.query_template_type)
  let resource_description = resource_description()
  let resource_threshold = resource_threshold(slo.threshold, slo.window_in_days)
  let slo_specification = slo_specification(slo)
  let resource_name =
    resource_name(slo.team_name, slo.service_name, slo.sli.name)
  let tags =
    get_tags(
      slo.team_name,
      slo.service_name,
      slo.sli.name,
      slo.sli.query_template_type.name,
    )
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
