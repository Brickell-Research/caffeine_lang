import caffeine/phase_1/parser/specification/unresolved_query_template_specification
import caffeine/types/specification_types.{GoodOverBadQueryTemplateUnresolved}

pub fn parse_query_template_types_test() {
  let expected_query_template_types = [
    GoodOverBadQueryTemplateUnresolved(
      numerator_query: "sum(rate(http_requests_total{status!~'5..'}[5m]))",
      denominator_query: "sum(rate(http_requests_total[5m]))",
      filters: ["team_name", "accepted_status_codes"],
    ),
  ]

  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types.yaml",
    )
  assert actual == Ok(expected_query_template_types)
}

pub fn parse_query_template_types_missing_filters_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_filters.yaml",
    )
  assert actual == Error("Missing filters")
}

pub fn parse_query_template_types_missing_numerator_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_numerator.yaml",
    )
  assert actual == Error("Missing numerator_query")
}

pub fn parse_query_template_types_missing_denominator_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_denominator.yaml",
    )
  assert actual == Error("Missing denominator_query")
}
