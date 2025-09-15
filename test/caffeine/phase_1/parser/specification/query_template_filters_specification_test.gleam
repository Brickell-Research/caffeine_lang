import caffeine/phase_1/parser/specification/query_template_filters_specification
import caffeine/types/intermediate_representation

pub fn parse_query_template_filters_test() {
  let expected_query_template_filters = [
    intermediate_representation.QueryTemplateFilter(
      attribute_name: "team_name",
      attribute_type: intermediate_representation.String,
    ),
    intermediate_representation.QueryTemplateFilter(
      attribute_name: "number_of_users",
      attribute_type: intermediate_representation.Integer,
    ),
    intermediate_representation.QueryTemplateFilter(
      attribute_name: "accepted_status_codes",
      attribute_type: intermediate_representation.List(
        intermediate_representation.String,
      ),
    ),
  ]

  let actual =
    query_template_filters_specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters.yaml",
    )
  assert actual == Ok(expected_query_template_filters)
}

pub fn parse_query_template_filters_missing_attribute_type_test() {
  let actual =
    query_template_filters_specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_missing_attribute_type.yaml",
    )
  assert actual == Error("Missing attribute_type")
}

// Note: This test is no longer relevant since we removed the required attribute
// pub fn parse_query_template_filters_missing_attribute_required_test() {
//   let actual =
//     query_template_filters_specification.parse_query_template_filters_specification(
//       "test/artifacts/specifications/query_template_filters_missing_attribute_required.yaml",
//     )
//   assert actual == Error("Missing required")
// }

pub fn parse_query_template_filters_missing_attribute_name_test() {
  let actual =
    query_template_filters_specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_missing_attribute_name.yaml",
    )
  assert actual == Error("Missing attribute_name")
}

pub fn parse_query_template_filters_unrecognized_attribute_type_test() {
  let actual =
    query_template_filters_specification.parse_query_template_filters_specification(
      "test/artifacts/specifications/query_template_filters_unrecognized_attribute_type.yaml",
    )
  assert actual == Error("Unknown attribute type: LargeNumber")
}
