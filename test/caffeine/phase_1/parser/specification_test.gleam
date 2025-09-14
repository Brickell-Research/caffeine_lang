import caffeine/phase_1/parser/specification
import caffeine/types/intermediate_representation
import caffeine/types/specification_types.{
  GoodOverBadQueryTemplateUnresolved, ServiceUnresolved, SliTypeUnresolved,
}

pub fn parse_services_test() {
  let expected_services = [
    ServiceUnresolved(name: "reliable_service", sli_types: [
      "latency",
      "error_rate",
    ]),
    ServiceUnresolved(name: "unreliable_service", sli_types: [
      "error_rate",
    ]),
  ]

  let actual =
    specification.parse_services_specification(
      "test/artifacts/specifications/services.yaml",
    )
  assert actual == Ok(expected_services)
}

pub fn parse_services_missing_sli_types_test() {
  let actual =
    specification.parse_services_specification(
      "test/artifacts/specifications/services_missing_sli_types.yaml",
    )
  assert actual == Error("Missing sli_types")
}

pub fn parse_services_missing_name_test() {
  let actual =
    specification.parse_services_specification(
      "test/artifacts/specifications/services_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}

pub fn parse_query_template_filters_test() {
  let expected_query_template_filters = [
    intermediate_representation.QueryTemplateFilter(
      attribute_name: "team_name",
      attribute_type: intermediate_representation.String,
      required: True,
    ),
    intermediate_representation.QueryTemplateFilter(
      attribute_name: "number_of_users",
      attribute_type: intermediate_representation.Integer,
      required: True,
    ),
    intermediate_representation.QueryTemplateFilter(
      attribute_name: "accepted_status_codes",
      attribute_type: intermediate_representation.List(
        intermediate_representation.String,
      ),
      required: False,
    ),
  ]

  let actual =
    specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters.yaml",
    )
  assert actual == Ok(expected_query_template_filters)
}

pub fn parse_query_template_filters_missing_attribute_type_test() {
  let actual =
    specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_missing_attribute_type.yaml",
    )
  assert actual == Error("Missing attribute_type")
}

pub fn parse_query_template_filters_missing_attribute_required_test() {
  let actual =
    specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_missing_attribute_required.yaml",
    )
  assert actual == Error("Missing required")
}

pub fn parse_query_template_filters_missing_attribute_name_test() {
  let actual =
    specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_missing_attribute_name.yaml",
    )
  assert actual == Error("Missing attribute_name")
}

pub fn parse_query_template_filters_unrecognized_attribute_type_test() {
  let actual =
    specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_unrecognized_attribute_type.yaml",
    )
  assert actual == Error("Unknown attribute type: LargeNumber")
}

pub fn parse_sli_types_test() {
  let expected_sli_types = [
    SliTypeUnresolved(name: "latency", query_template_type: "good_over_bad"),
    SliTypeUnresolved(name: "error_rate", query_template_type: "good_over_bad"),
  ]

  let actual =
    specification.parse_sli_types_specification(
      "test/artifacts/specifications/sli_types.yaml",
    )
  assert actual == Ok(expected_sli_types)
}

pub fn parse_sli_types_missing_name_test() {
  let actual =
    specification.parse_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}

pub fn parse_sli_types_missing_query_template_test() {
  let actual =
    specification.parse_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_query_template.yaml",
    )
  assert actual == Error("Missing query_template_type")
}

pub fn parse_query_template_types_test() {
  let expected_query_template_types = [
    GoodOverBadQueryTemplateUnresolved(
      numerator_query: "sum(rate(http_requests_total{status!~'5..'}[5m]))",
      denominator_query: "sum(rate(http_requests_total[5m]))",
      filters: ["team_name", "accepted_status_codes"],
    ),
  ]

  let actual =
    specification.parse_query_template_types_specification(
      "test/artifacts/specifications/query_template_types.yaml",
    )
  assert actual == Ok(expected_query_template_types)
}

pub fn parse_query_template_types_missing_filters_test() {
  let actual =
    specification.parse_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_filters.yaml",
    )
  assert actual == Error("Missing filters")
}

pub fn parse_query_template_types_missing_numerator_test() {
  let actual =
    specification.parse_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_numerator.yaml",
    )
  assert actual == Error("Missing numerator_query")
}

pub fn parse_query_template_types_missing_denominator_test() {
  let actual =
    specification.parse_query_template_types_specification(
      "test/artifacts/specifications/query_template_types_missing_denominator.yaml",
    )
  assert actual == Error("Missing denominator_query")
}
