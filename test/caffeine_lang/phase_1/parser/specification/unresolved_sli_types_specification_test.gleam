import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/types/unresolved/unresolved_sli_type
import gleam/dict
import gleam/result
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn parse_unresolved_sli_types_specification_test() {
  describe("parse_unresolved_sli_types_specification", fn() {
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

      let actual =
        unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
          "test/caffeine_lang/artifacts/specifications/sli_types.yaml",
        )

      actual
      |> gleeunit.equal(Ok(expected_sli_types))
    })

    it("should return an error when name is missing", fn() {
      let actual =
        unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
          "test/caffeine_lang/artifacts/specifications/sli_types_missing_name.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal("Missing name")
        Ok(_) -> panic as "Expected error"
      }
    })

    it("should return an error when query_template_type is missing", fn() {
      let actual =
        unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
          "test/caffeine_lang/artifacts/specifications/sli_types_missing_query_template.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal("Missing query_template_type")
        Ok(_) -> panic as "Expected error"
      }
    })
  })
}
