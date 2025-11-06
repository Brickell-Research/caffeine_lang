import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/types/unresolved/unresolved_sli_type
import gleam/dict
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn parse_unresolved_sli_types_specification_test() {
  describe("parse_unresolved_sli_types_specification", fn() {
    describe("valid sli types", fn() {
      it("should parse valid sli types", fn() {
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

        unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
          "test/caffeine_lang/artifacts/specifications/sli_types.yaml",
        )
        |> gleeunit.equal(Ok(expected_sli_types))
      })
    })

    describe("error cases", fn() {
      it("should return an error when name is missing", fn() {
        unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
          "test/caffeine_lang/artifacts/specifications/sli_types_missing_name.yaml",
        )
        |> gleeunit.equal(Error("Missing name"))
      })

      it("should return an error when query_template_type is missing", fn() {
        unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
          "test/caffeine_lang/artifacts/specifications/sli_types_missing_query_template.yaml",
        )
        |> gleeunit.equal(Error("Missing query_template_type"))
      })
    })
  })
}
