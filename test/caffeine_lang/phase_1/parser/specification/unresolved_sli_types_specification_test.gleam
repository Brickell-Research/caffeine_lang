import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/types/unresolved/unresolved_sli_type
import gleam/dict
import startest/expect

pub fn parse_sli_types_test() {
  let expected_sli_types = [
    unresolved_sli_type.SliType(
      name: "latency",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: [
        "team_name",
        "accepted_status_codes",
      ],
    ),
    unresolved_sli_type.SliType(
      name: "error_rate",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: ["number_of_users"],
    ),
  ]

  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types.yaml",
    )
  expect.to_equal(actual, Ok(expected_sli_types))
}

pub fn parse_sli_types_missing_name_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_name.yaml",
    )
  expect.to_equal(actual, Error("Missing name"))
}

pub fn parse_sli_types_missing_query_template_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_query_template.yaml",
    )
  expect.to_equal(actual, Error("Missing query_template_type"))
}
