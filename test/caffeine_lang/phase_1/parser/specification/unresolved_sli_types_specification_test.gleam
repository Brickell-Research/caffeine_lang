import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/phase_1/unresolved/types as unresolved_types
import gleam/dict

pub fn parse_sli_types_test() {
  let expected_sli_types = [
    unresolved_types.SliTypeUnresolved(
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
    unresolved_types.SliTypeUnresolved(
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
  assert actual == Ok(expected_sli_types)
}

pub fn parse_sli_types_missing_name_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}

pub fn parse_sli_types_missing_query_template_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_query_template.yaml",
    )
  assert actual == Error("Missing query_template_type")
}
