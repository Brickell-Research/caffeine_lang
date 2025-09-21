import caffeine_lang/common_types/accepted_types
import caffeine_lang/phase_2/ast/types as ast_types
import caffeine_lang/phase_4/resolved/types as resolved_types
import caffeine_lang/phase_5/terraform/datadog
import gleam/dict

pub fn set_resource_comment_header_test() {
  let expected = "# SLO created by EzSLO for team - Type: type"
  let actual = datadog.set_resource_comment_header("team", "type")
  assert actual == expected
}

pub fn resource_threshold_test() {
  let expected =
    "thresholds {\n    timeframe = \"45d\"\n    target    = 0.95\n  }"
  let actual = datadog.resource_threshold(0.95, 45)
  assert actual == expected
}

pub fn resource_target_threshold_test() {
  let expected = "target = 0.95"
  let actual = datadog.resource_target_threshold(0.95)
  assert actual == expected
}

pub fn resource_top_line_test() {
  let expected =
    "resource \"datadog_service_level_objective\" \"team_service_type\" {"
  let actual = datadog.resource_top_line("team", "service", "type")
  assert actual == expected
}

pub fn resource_description_test() {
  let expected = "description = \"SLO created by caffeine\""
  let actual = datadog.resource_description()
  assert actual == expected
}

pub fn get_tags_test() {
  let _tags =
    dict.new()
    |> dict.insert("managed-by", "caffeine")
    |> dict.insert("team", "platform")
    |> dict.insert("environment", "production")

  let expected =
    "tags = [\"managed-by:caffeine\", \"team:platform\", \"service:production\", \"sli:good_over_bad\"]"
  let actual = datadog.get_tags("platform", "production", "good_over_bad")
  assert actual == expected
}

pub fn tf_resource_name_test() {
  let expected =
    "resource \"datadog_service_level_objective\" team_service_type {"
  let actual = datadog.tf_resource_name("team", "service", "type")
  assert actual == expected
}

pub fn resource_type_test() {
  let expected = "type        = \"metric\""
  let actual =
    datadog.resource_type(ast_types.QueryTemplateType(
      specification_of_query_templates: [],
      name: "good_over_bad",
    ))
  assert actual == expected
}

pub fn slo_specification_test() {
  let expected =
    "query {\n    denominator = \"#{denominator_query}\"\n    numerator = \"#{numerator_query}\"\n  }\n"
  let actual =
    datadog.slo_specification(resolved_types.ResolvedSlo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: resolved_types.ResolvedSli(
        query_template_type: ast_types.QueryTemplateType(
          specification_of_query_templates: [
            ast_types.BasicType(
              attribute_name: "numerator_query",
              attribute_type: accepted_types.String,
            ),
            ast_types.BasicType(
              attribute_name: "denominator_query",
              attribute_type: accepted_types.String,
            ),
          ],
          name: "good_over_bad",
        ),
        metric_attributes: dict.from_list([
          #("numerator", "#{numerator_query}"),
          #("denominator", "#{denominator_query}"),
        ]),
      ),
    ))
  assert actual == expected
}

pub fn full_resource_body_test() {
  let expected =
    "# SLO created by EzSLO for badass_platform_team - Type: good_over_bad
resource \"datadog_service_level_objective\" \"badass_platform_team_super_scalabale_web_service_good_over_bad\" {
  name = \"badass_platform_team_super_scalabale_web_service_good_over_bad\"
  type        = \"metric\"
  description = \"SLO created by caffeine\"
  
  query {
    denominator = \"#{denominator_query}\"
    numerator = \"#{numerator_query}\"
  }

  thresholds {
    timeframe = \"30d\"
    target    = 99.5
  }

  tags = [\"managed-by:caffeine\", \"team:badass_platform_team\", \"service:super_scalabale_web_service\", \"sli:good_over_bad\"]
}"

  let actual =
    datadog.full_resource_body(resolved_types.ResolvedSlo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: resolved_types.ResolvedSli(
        query_template_type: ast_types.QueryTemplateType(
          specification_of_query_templates: [
            ast_types.BasicType(
              attribute_name: "numerator_query",
              attribute_type: accepted_types.String,
            ),
            ast_types.BasicType(
              attribute_name: "denominator_query",
              attribute_type: accepted_types.String,
            ),
          ],
          name: "good_over_bad",
        ),
        metric_attributes: dict.from_list([
          #("numerator", "#{numerator_query}"),
          #("denominator", "#{denominator_query}"),
        ]),
      ),
    ))

  assert actual == expected
}
