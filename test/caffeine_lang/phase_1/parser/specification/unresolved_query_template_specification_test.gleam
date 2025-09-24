import caffeine_lang/cql/parser.{ExpContainer, Primary, PrimaryWord, Word}
import caffeine_lang/phase_1/parser/specification/unresolved_query_template_specification
import caffeine_lang/types/unresolved/unresolved_query_template_type
import startest.{describe, it}
import startest/expect

pub fn unresolved_query_template_specification_tests() {
  describe("Unresolved Query Template Specification Parser", [
    describe("parse_unresolved_query_template_types_specification", [
      it("parses valid query template types", fn() {
        let expected_query_template_types = [
          unresolved_query_template_type.QueryTemplateType(
            name: "good_over_bad",
            specification_of_query_templates: [
              "team_name",
              "accepted_status_codes",
            ],
            query: ExpContainer(Primary(PrimaryWord(Word("")))),
          ),
        ]

        let actual =
          unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
            "test/artifacts/specifications/query_template_types.yaml",
          )
        expect.to_equal(actual, Ok(expected_query_template_types))
      }),
      it("returns error when specification_of_query_templates is missing", fn() {
        let actual =
          unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
            "test/artifacts/specifications/query_template_types_missing_specification_of_query_templates.yaml",
          )
        expect.to_equal(actual, Error("Missing specification_of_query_templates"))
      }),
      it("returns error when name is missing", fn() {
        let actual =
          unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
            "test/artifacts/specifications/query_template_types_missing_name.yaml",
          )
        expect.to_equal(actual, Error("Missing name"))
      }),
    ]),
  ])
}
