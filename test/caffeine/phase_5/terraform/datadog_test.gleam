import caffeine/phase_5/terraform/datadog
import caffeine/types/intermediate_representation.{QueryTemplateType}
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
    datadog.resource_type(
      QueryTemplateType(
        metric_attributes: [],
        name: "good_over_bad",
      ),
    )
  assert actual == expected
}
