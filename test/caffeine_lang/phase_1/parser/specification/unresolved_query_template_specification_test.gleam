import caffeine_lang/phase_1/parser/specification/unresolved_query_template_specification
import caffeine_lang/types/unresolved/unresolved_query_template_type
import cql/parser.{Div, ExpContainer, OperatorExpr, Primary, PrimaryWord, Word}
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn parse_unresolved_query_template_types_specification_test() {
  describe("parse_unresolved_query_template_types_specification", fn() {
    describe("valid query template types", fn() {
      it("should parse valid query template types", fn() {
        let expected_query_template_types = [
          unresolved_query_template_type.QueryTemplateType(
            name: "good_over_bad",
            specification_of_query_templates: [
              "team_name",
              "accepted_status_codes",
            ],
            query: ExpContainer(OperatorExpr(
              Primary(PrimaryWord(Word("numerator"))),
              Primary(PrimaryWord(Word("denominator"))),
              Div,
            )),
          ),
        ]

        unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
          "test/caffeine_lang/artifacts/specifications/query_template_types.yaml",
        )
        |> gleeunit.equal(Ok(expected_query_template_types))
      })
    })

    describe("error cases", fn() {
      it(
        "should return an error when specification_of_query_templates is missing",
        fn() {
          unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
            "test/caffeine_lang/artifacts/specifications/query_template_types_missing_specification_of_query_templates.yaml",
          )
          |> gleeunit.equal(Error("Missing specification_of_query_templates"))
        },
      )

      it("should return an error when name is missing", fn() {
        unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
          "test/caffeine_lang/artifacts/specifications/query_template_types_missing_name.yaml",
        )
        |> gleeunit.equal(Error("Missing name"))
      })

      it("should return an error when query is empty", fn() {
        unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
          "test/caffeine_lang/artifacts/specifications/query_template_types_missing_query.yaml",
        )
        |> gleeunit.equal(Error("Empty query string is not allowed"))
      })
    })
  })
}
