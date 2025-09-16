import caffeine_lang/phase_5/terraform/datadog
import caffeine_lang/types/ast.{QueryTemplateFilter, QueryTemplateType}
import caffeine_lang/types/intermediate_representation.{ResolvedSli, ResolvedSlo}
import caffeine_lang/types/accepted_types
import gleam/dict

pub fn set_resource_comment_header_test() {
  let expected = "# SLO created by EzSLO for team - Type: type"
  let actual = datadog.set_resource_comment_header("team", "type")
  assert actual == expected
}

pub fn resource_threshold_test() {
  let expected =
    "thresholds {\n    timeframe = \"30d\"\n    target    = 0.95\n  }"
  let actual = datadog.resource_threshold(0.95)
  assert actual == expected
}

pub fn resource_time_frame_test() {
  let expected = "timeframe = \"30d\""
  let actual = datadog.resource_time_frame()
  assert actual == expected
}

pub fn resource_target_threshold_test() {
  let expected = "target = 0.95"
  let actual = datadog.resource_target_threshold(0.95)
  assert actual == expected
}

pub fn resource_top_line_test() {
  let expected =
    "resource \"datadog_service_level_objective\" team_service_type {"
  let actual = datadog.resource_top_line("team", "service", "type")
  assert actual == expected
}

pub fn resource_description_test() {
  let expected = "description = \"SLO created by caffeine\""
  let actual = datadog.resource_description()
  assert actual == expected
}

pub fn get_tags_test() {
  let tags =
    dict.new()
    |> dict.insert("managed-by", "caffeine")
    |> dict.insert("team", "platform")
    |> dict.insert("environment", "production")

  let expected =
    "tags = [\"environment:production\", \"managed-by:caffeine\", \"team:platform\"]"
  let actual = datadog.get_tags(tags)
  assert actual == expected
}

pub fn get_tags_empty_test() {
  let tags = dict.new()
  let expected = "tags = []"
  let actual = datadog.get_tags(tags)
  assert actual == expected
}

pub fn get_tags_single_test() {
  let tags =
    dict.new()
    |> dict.insert("managed-by", "caffeine")

  let expected = "tags = [\"managed-by:caffeine\"]"
  let actual = datadog.get_tags(tags)
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
    datadog.resource_type(QueryTemplateType(
      metric_attributes: [],
      name: "good_over_bad",
    ))
  assert actual == expected
}

pub fn slo_specification_test() {
  let expected =
    "query {\ndenominator = #{denominator_query}\nnumerator = #{numerator_query}\n}\n"
  let actual =
    datadog.slo_specification(ResolvedSlo(
      window_in_days: 30,
      threshold: 99.5,
      service_name: "super_scalabale_web_service",
      team_name: "badass_platform_team",
      sli: ResolvedSli(
        query_template_type: QueryTemplateType(
          metric_attributes: [
            QueryTemplateFilter(
              attribute_name: "numerator_query",
              attribute_type: accepted_types.String,
            ),
            QueryTemplateFilter(
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
