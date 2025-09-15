import caffeine_lang/phase_1/parser/specification/unresolved_query_template_specification
import caffeine_lang/types/specification_types.{QueryTemplateTypeUnresolved}

pub fn parse_query_template_types_test() {
  let expected_query_template_types = [
    QueryTemplateTypeUnresolved(
      name: "good_over_bad",
      metric_attributes: ["team_name", "accepted_status_codes"],
    ),
  ]

  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types.yaml",
    )
  assert actual == Ok(expected_query_template_types)
}

pub fn parse_query_template_types_missing_metric_attributes_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_metric_attributes.yaml",
    )
  assert actual == Error("Missing metric_attributes")
}

pub fn parse_query_template_types_missing_name_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}
