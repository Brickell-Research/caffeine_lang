import caffeine_lang/phase_1/parser/common_parse_test_utils
import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/types/unresolved/unresolved_sli_type
import gleam/dict
import startest.{describe, it}
import startest/expect

fn assert_parse_error(file_path: String, expected: String) {
  common_parse_test_utils.assert_parse_error(
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification,
    file_path,
    expected,
  )
}

pub fn unresolved_sli_types_specification_tests() {
  describe("Unresolved SLI Types Specification Parser", [
    describe("parse_unresolved_sli_types_specification", [
      it("parses valid SLI types", fn() {
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
      }),
      it("returns error when name is missing", fn() {
        assert_parse_error(
          "test/artifacts/specifications/sli_types_missing_name.yaml",
          "Missing name",
        )
      }),
      it("returns error when query_template_type is missing", fn() {
        assert_parse_error(
          "test/artifacts/specifications/sli_types_missing_query_template.yaml",
          "Missing query_template_type",
        )
      }),
    ]),
  ])
}
